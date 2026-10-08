import PencilKit
import SwiftUI

/// Fixed notebook ruling, independent of text layout and seeded per card.
/// The crayon texture is tinted with the appearance's rule color.
struct NotebookRules: View {
    let seed: UUID
    var interval: CGFloat = 42
    var lineWidth: CGFloat = 1.75
    var wiggle: CGFloat = 1.4
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            let request = NotebookRuleRequest(seed: seed, size: geometry.size, scale: scale,
                                              interval: interval, lineWidth: lineWidth, wiggle: wiggle)
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(Color.chineseRoomRule)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: request) {
                guard let result = await NotebookRuleRenderer.shared.image(for: request),
                      !Task.isCancelled else { return }
                image = result
            }
        }
        .padding(.horizontal, 36)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NotebookRuleRequest: Hashable, Sendable {
    let seed: UUID
    let size: CGSize
    let scale: CGFloat
    let interval: CGFloat
    let lineWidth: CGFloat
    let wiggle: CGFloat

    init(seed: UUID, size: CGSize, scale: CGFloat, interval: CGFloat, lineWidth: CGFloat, wiggle: CGFloat) {
        self.seed = seed
        self.scale = max(1, scale)
        self.size = CGSize(width: size.width.isFinite ? ceil(max(0, size.width) * self.scale) / self.scale : 0,
                           height: size.height.isFinite ? ceil(max(0, size.height) * self.scale) / self.scale : 0)
        self.interval = max(8, interval)
        self.lineWidth = max(0.25, lineWidth)
        self.wiggle = min(max(0, wiggle), self.interval / 4)
    }

    var key: NSString {
        "\(seed):\(size.width):\(size.height):\(scale):\(interval):\(lineWidth):\(wiggle)" as NSString
    }
}

private actor NotebookRuleRenderer {
    static let shared = NotebookRuleRenderer()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    func image(for request: NotebookRuleRequest) -> UIImage? {
        guard !Task.isCancelled, request.size.width > 0, request.size.height > 0 else { return nil }
        if let cached = cache.object(forKey: request.key) { return cached }
        let image: UIImage? = autoreleasepool {
            let seed = request.seed.uuidString.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
            let ink = PKInk(.crayon, color: UIColor(red: 0.94, green: 0.81, blue: 0.34, alpha: 1))
            let strokes = (1...max(1, Int(ceil(request.size.height / request.interval)))).map { row in
                // Each row has its own random stream, stable when the card resizes.
                var random = NotebookRuleRandom(state: seed &+ UInt64(row) &* 0x9E3779B97F4A7C15)
                let anchors = (0...Int(ceil(request.size.width / 36)) + 2).map { _ in random.unit() * 2 - 1 }
                let points = (0...Int(ceil((request.size.width + 32) / 6))).map { index in
                    let x = CGFloat(index) * 6 - 16
                    let position = max(0, x) / 36
                    let anchor = min(Int(position), anchors.count - 2)
                    let fraction = position - CGFloat(anchor)
                    let blend = fraction * fraction * (3 - 2 * fraction)
                    let offset = anchors[anchor] + (anchors[anchor + 1] - anchors[anchor]) * blend
                    return PKStrokePoint(
                        location: CGPoint(x: x, y: CGFloat(row) * request.interval + offset * request.wiggle),
                        timeOffset: Double(index) * 0.01,
                        size: CGSize(width: request.lineWidth, height: request.lineWidth),
                        opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                    )
                }
                return PKStroke(ink: ink,
                    path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)),
                    randomSeed: UInt32(truncatingIfNeeded: seed &+ UInt64(row)))
            }
            var result: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                result = PKDrawing(strokes: strokes).image(from: CGRect(origin: .zero, size: request.size),
                                                          scale: request.scale)
            }
            return result
        }
        guard let image else { return nil }
        cache.setObject(image, forKey: request.key,
                        cost: Int(request.size.width * request.size.height * request.scale * request.scale) * 4)
        return image
    }
}

private struct NotebookRuleRandom {
    var state: UInt64
    mutating func unit() -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return CGFloat(value >> 11) / CGFloat(UInt64(1) << 53)
    }
}
