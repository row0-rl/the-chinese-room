import PencilKit
import SwiftUI

/// PencilKit supplies the graphite grain; seeded geometry supplies the hand-drawn outline.
struct PencilRectangle: View {
    static let contentInset: CGFloat = 32
    // Keep the exact top/bottom pencil marks when the paper changes height.
    fileprivate static let referenceHeight: CGFloat = 180
    fileprivate static let capHeight: CGFloat = 44
    static let placeholderSeed = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    let seed: UUID
    var cornerRadius: CGFloat = 8
    var cornerJitter: CGFloat = 6
    var lineWidth: CGFloat = 3.3
    var wobble: CGFloat = 3
    var graphiteOpacity: Double = 0.55
    @Environment(\.displayScale) private var displayScale
    @State private var renderedBorder: RenderedBorder?

    var body: some View {
        GeometryReader { geometry in
            let request = PencilBorderRequest(
                seed: seed,
                size: CGSize(width: geometry.size.width, height: Self.referenceHeight),
                scale: displayScale,
                cornerRadius: cornerRadius,
                cornerJitter: cornerJitter,
                lineWidth: lineWidth,
                wobble: wobble
            )
            ZStack {
                if let renderedBorder, renderedBorder.seed == seed {
                    Image(uiImage: renderedBorder.image)
                        .renderingMode(.template)
                        .resizable(capInsets: EdgeInsets(top: Self.capHeight, leading: 0, bottom: Self.capHeight, trailing: 0))
                        .foregroundStyle(Color.chineseRoomInk)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: request) {
                // Height is handled by the stretchable middle, so growing the card
                // never rerasterizes or stretches its top edge and corners.
                if renderedBorder != nil {
                    do { try await Task.sleep(for: .milliseconds(40)) }
                    catch { return }
                }
                guard !Task.isCancelled,
                      let image = await PencilBorderRenderer.shared.image(for: request),
                      !Task.isCancelled else { return }
                renderedBorder = RenderedBorder(seed: seed, image: image)
            }
        }
        .opacity(graphiteOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct RenderedBorder {
        let seed: UUID
        let image: UIImage
    }
}

private struct PencilBorderRequest: Hashable, Sendable {
    let seed: UUID
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat
    let cornerRadius: CGFloat
    let cornerJitter: CGFloat
    let lineWidth: CGFloat
    let wobble: CGFloat

    init(seed: UUID, size: CGSize, scale: CGFloat, cornerRadius: CGFloat, cornerJitter: CGFloat = 6, lineWidth: CGFloat, wobble: CGFloat) {
        self.seed = seed
        self.scale = max(1, scale)
        pixelWidth = size.width.isFinite ? Int((max(0, size.width) * self.scale).rounded()) : 0
        pixelHeight = size.height.isFinite ? Int((max(0, size.height) * self.scale).rounded()) : 0
        self.cornerRadius = max(0, cornerRadius)
        self.cornerJitter = max(0, cornerJitter)
        self.lineWidth = max(0.5, lineWidth)
        self.wobble = max(0, wobble)
    }

    var size: CGSize {
        CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale)
    }

    var cacheKey: NSString {
        "\(seed.uuidString):\(pixelWidth):\(pixelHeight):\(scale):\(cornerRadius):\(cornerJitter):\(lineWidth):\(wobble)" as NSString
    }
}

/// Matches the card fill and clipping to the pencil's centerline.
struct PencilRectangleShape: Shape {
    let seed: UUID
    var cornerRadius: CGFloat = 8
    var cornerJitter: CGFloat = 6
    var lineWidth: CGFloat = 3.3
    var wobble: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let request = PencilBorderRequest(
            seed: seed, size: CGSize(width: rect.width, height: PencilRectangle.referenceHeight), scale: 1,
            cornerRadius: cornerRadius, cornerJitter: cornerJitter, lineWidth: lineWidth, wobble: wobble
        )
        return PencilBorderDrawing.outlinePath(for: request, height: rect.height)
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// Serial, off-main rendering with a bounded cache shared by history and prefetched cards.
private actor PencilBorderRenderer {
    static let shared = PencilBorderRenderer()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    func image(for request: PencilBorderRequest) -> UIImage? {
        guard !Task.isCancelled, request.pixelWidth > 0, request.pixelHeight > 0 else { return nil }
        if let cached = cache.object(forKey: request.cacheKey) { return cached }

        let image: UIImage? = autoreleasepool {
            let drawing = PencilBorderDrawing.make(request)
            var image: UIImage?
            // Render black graphite; PencilRectangle tints it for the current appearance.
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: CGRect(origin: .zero, size: request.size), scale: request.scale)
            }
            return image
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: request.cacheKey, cost: request.pixelWidth * request.pixelHeight * 4)
        return image
    }
}

private enum PencilBorderDrawing {
    private static func generator(seed: UUID) -> PencilBorderRandom {
        // UUID bytes, rather than Swift's process-randomized hash, keep saved cards reproducible.
        let value = seed.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return PencilBorderRandom(state: value)
    }

    private static func samples(for request: PencilBorderRequest, random: inout PencilBorderRandom) -> [Sample] {
        let jitter = min(request.cornerJitter, min(request.size.width, request.size.height) / 12)
        // Reserve room for displaced joins, side bends and the pencil's particle spread.
        let inset = request.lineWidth + request.wobble + jitter + 1
        let rect = CGRect(origin: .zero, size: request.size).insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else { return [] }
        // Widen the corner regions with the requested range so the old radius
        // cannot silently cap larger offsets. Keep the joins safely ordered.
        let radius = min(max(request.cornerRadius, jitter * 2.5), min(rect.width, rect.height) / 4)
        return outline(in: rect, radius: radius, cornerJitter: min(jitter, radius * 0.4),
                       wobble: min(request.wobble, min(rect.width, rect.height) * 0.08), random: &random)
    }

    static func outlinePath(for request: PencilBorderRequest, height: CGFloat) -> Path {
        var random = generator(seed: request.seed)
        let samples = samples(for: request, random: &random)
        let cap = PencilRectangle.capHeight
        let targetCap = min(cap, height / 2)
        func resized(_ point: CGPoint) -> CGPoint {
            let y: CGFloat
            if point.y <= cap {
                y = point.y * targetCap / cap
            } else if point.y >= request.size.height - cap {
                y = height - (request.size.height - point.y) * targetCap / cap
            } else {
                y = targetCap + (point.y - cap) * (height - targetCap * 2) / (request.size.height - cap * 2)
            }
            return CGPoint(x: point.x, y: y)
        }
        return Path { path in
            guard let first = samples.first else { return }
            path.move(to: resized(first.point))
            for sample in samples.dropFirst() { path.addLine(to: resized(sample.point)) }
            path.closeSubpath()
        }
    }

    static func make(_ request: PencilBorderRequest) -> PKDrawing {
        var random = generator(seed: request.seed)
        let samples = samples(for: request, random: &random)
        guard samples.count > 1 else { return PKDrawing() }

        let pressurePhase = random.unit() * .pi * 2
        let widthPhase = random.unit() * .pi * 2
        // Seeded thickness anchors replace a repeating wave. Smooth interpolation
        // keeps the changes gradual, including where the closed stroke joins itself.
        let widthAnchors = (0..<18).map { _ in 0.65 + random.unit() * 0.75 }
        let coverageAnchors = (0..<23).map { _ in 0.45 + random.unit() * 0.55 }
        let strokes = (0..<2).map { pass in
            let points = samples.enumerated().map { index, sample in
                let progress = CGFloat(index) / CGFloat(samples.count - 1)
                let pressure = 0.72 + 0.16 * sin(progress * .pi * 12 + pressurePhase)
                let coverage = interpolate(coverageAnchors, at: progress)
                let width = request.lineWidth * (pass == 0 ? 1 : 0.65)
                    * interpolate(widthAnchors, at: progress)
                // A faint second pass leaves the slight retracing seen in a pencil sketch.
                let offset: CGFloat = pass == 0 ? 0 : 0.45 * sin(progress * .pi * 8 + widthPhase)
                let location = CGPoint(
                    x: sample.point.x + sample.normal.dx * offset,
                    y: sample.point.y + sample.normal.dy * offset
                )
                return PKStrokePoint(
                    location: location,
                    timeOffset: Double(index) * 0.008,
                    size: CGSize(width: width, height: width),
                    opacity: pressure * coverage * (pass == 0 ? 0.55 : 0.08),
                    force: pressure,
                    azimuth: .pi / 6,
                    altitude: .pi / 3,
                    secondaryScale: 1,
                    threshold: 0,
                    lateralJitter: 0.5 + 0.5 * (1 - coverage)
                )
            }
            return PKStroke(
                ink: PKInk(.pencil, color: .black),
                path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)),
                randomSeed: UInt32(truncatingIfNeeded: random.next())
            )
        }
        return PKDrawing(strokes: strokes)
    }

    private static func interpolate(_ anchors: [CGFloat], at progress: CGFloat) -> CGFloat {
        let position = progress * CGFloat(anchors.count)
        let index = Int(position) % anchors.count
        let fraction = position - floor(position)
        let blend = fraction * fraction * (3 - 2 * fraction)
        return anchors[index] + (anchors[(index + 1) % anchors.count] - anchors[index]) * blend
    }

    private struct Sample {
        let point: CGPoint
        let normal: CGVector
    }

    private static func outline(
        in rect: CGRect, radius r: CGFloat, cornerJitter: CGFloat, wobble: CGFloat, random: inout PencilBorderRandom
    ) -> [Sample] {
        var samples: [Sample] = []

        // Clockwise edge/corner joins, two near each corner. Independent offsets
        // stay below half the radius, preserving their ordering even on small cards.
        let joins = [
            CGPoint(x: rect.minX + r, y: rect.minY),
            CGPoint(x: rect.maxX - r, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + r),
            CGPoint(x: rect.maxX, y: rect.maxY - r),
            CGPoint(x: rect.maxX - r, y: rect.maxY),
            CGPoint(x: rect.minX + r, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - r),
            CGPoint(x: rect.minX, y: rect.minY + r)
        ].map { point in
            CGPoint(x: point.x + (random.unit() * 2 - 1) * cornerJitter,
                    y: point.y + (random.unit() * 2 - 1) * cornerJitter)
        }

        func tangent(from start: CGPoint, to end: CGPoint) -> CGVector {
            let length = max(0.001, hypot(end.x - start.x, end.y - start.y))
            return CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
        }

        func line(from start: CGPoint, to end: CGPoint) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let direction = tangent(from: start, to: end)
            let normal = CGVector(dx: direction.dy, dy: -direction.dx)
            let count = max(1, Int(ceil(length / 2)))
            let phase = random.unit() * .pi * 2
            let ripplePhase = random.unit() * .pi * 2
            let finePhase = random.unit() * .pi * 2
            let bendFrequency = 0.65 + random.unit() * 1.35
            let rippleFrequency = 2 + random.unit() * 2.5
            let fineFrequency = 5 + random.unit() * 2
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                // Each edge has its own broad bends and finer ripples, all smoothly bounded.
                // Zero displacement and slope at the joins preserve the corner tangents.
                let envelope = sin(.pi * t)
                let deviation = wobble * envelope * envelope
                    * (0.5 * sin(.pi * 2 * bendFrequency * t + phase)
                        + 0.35 * sin(.pi * 2 * rippleFrequency * t + ripplePhase)
                        + 0.15 * sin(.pi * 2 * fineFrequency * t + finePhase))
                samples.append(Sample(
                    point: CGPoint(
                        x: start.x + (end.x - start.x) * t + normal.dx * deviation,
                        y: start.y + (end.y - start.y) * t + normal.dy * deviation
                    ),
                    normal: normal
                ))
            }
        }

        func corner(from start: CGPoint, to end: CGPoint, incoming: CGVector, outgoing: CGVector) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            // Approximate a quarter circle, shortening handles for narrow, uneven corners.
            let handle = min(distance * 0.39, min(abs(end.x - start.x), abs(end.y - start.y)) * 0.75)
            let control1 = CGPoint(x: start.x + incoming.dx * handle, y: start.y + incoming.dy * handle)
            let control2 = CGPoint(x: end.x - outgoing.dx * handle, y: end.y - outgoing.dy * handle)
            let count = max(4, Int(ceil(distance)))
            for index in 0..<count {
                let t = CGFloat(index) / CGFloat(count)
                let u = 1 - t
                let derivative = CGVector(
                    dx: 3 * u * u * (control1.x - start.x) + 6 * u * t * (control2.x - control1.x) + 3 * t * t * (end.x - control2.x),
                    dy: 3 * u * u * (control1.y - start.y) + 6 * u * t * (control2.y - control1.y) + 3 * t * t * (end.y - control2.y)
                )
                let speed = max(0.001, hypot(derivative.dx, derivative.dy))
                samples.append(Sample(
                    point: CGPoint(
                        x: u * u * u * start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * end.x,
                        y: u * u * u * start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * end.y
                    ),
                    normal: CGVector(dx: derivative.dy / speed, dy: -derivative.dx / speed)
                ))
            }
        }

        let directions = stride(from: 0, to: joins.count, by: 2).map {
            tangent(from: joins[$0], to: joins[$0 + 1])
        }
        for edge in 0..<4 {
            let start = joins[edge * 2]
            let end = joins[edge * 2 + 1]
            let nextEdge = (edge + 1) % 4
            line(from: start, to: end)
            corner(from: end, to: joins[nextEdge * 2], incoming: directions[edge], outgoing: directions[nextEdge])
        }
        if let first = samples.first { samples.append(first) }
        return samples
    }
}

private struct PencilBorderRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }
}

#Preview("Pencil borders") {
    VStack(spacing: 24) {
        ForEach(0..<3) { index in
            Text("A little pencil, a different expression")
                .padding(PencilRectangle.contentInset)
                .frame(maxWidth: .infinity, minHeight: CGFloat(100 + index * 50))
                .background(Color.chineseRoomCard, in: PencilRectangleShape(seed: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!))
                .overlay(PencilRectangle(seed: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!))
        }
    }
    .padding(24)
    .background(Color.chineseRoomBackground)
}
