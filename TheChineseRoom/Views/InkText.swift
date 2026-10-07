import CoreText
import PencilKit
import SwiftUI
import UIKit

/// Native text layout and accessibility, with black lettering finished in pen ink.
struct InkText: View {
    let text: String
    @Environment(\.font) private var font
    @Environment(\.fontResolutionContext) private var fontContext
    @Environment(\.multilineTextAlignment) private var alignment
    @Environment(\.displayScale) private var scale

    init(_ text: String) { self.text = text }

    var body: some View {
        InkTextLabel(
            text: text,
            font: (font ?? AppFont.text(.body)).resolve(in: fontContext).ctFont as UIFont,
            alignment: alignment, scale: scale
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct InkTextLabel: UIViewRepresentable {
    let text: String
    let font: UIFont
    let alignment: TextAlignment
    let scale: CGFloat

    func makeUIView(context: Context) -> TextInkLabel {
        let label = TextInkLabel()
        label.numberOfLines = 0
        label.isAccessibilityElement = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: TextInkLabel, context: Context) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
        paragraph.lineBreakMode = .byWordWrapping
        label.configure(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor.black, .paragraphStyle: paragraph
        ]), scale: scale)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TextInkLabel, context: Context) -> CGSize? {
        let size = uiView.sizeThatFits(CGSize(width: proposal.width ?? .greatestFiniteMagnitude,
                                             height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

private final class TextInkLabel: UILabel {
    private var renderingTask: Task<Void, Never>?
    private var requestKey: NSString?
    private var inkImage: UIImage?
    private var inkScale: CGFloat = 1

    func configure(_ value: NSAttributedString, scale: CGFloat) {
        guard attributedText != value || inkScale != scale else { return }
        attributedText = value
        inkScale = scale
        requestKey = nil
        inkImage = nil
        renderingTask?.cancel()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let text = attributedText, bounds.width > 0, bounds.height > 0 else { return }
        let request = TextInkRequest(text: text, size: bounds.size, scale: inkScale)
        guard requestKey != request.key else { return }
        requestKey = request.key
        inkImage = nil
        renderingTask?.cancel()
        renderingTask = Task { [weak self] in
            guard let image = await TextInkRenderer.shared.image(for: request), !Task.isCancelled,
                  let self, self.requestKey == request.key else { return }
            self.inkImage = image
            self.setNeedsDisplay()
        }
    }

    override func drawText(in rect: CGRect) {
        if let inkImage { inkImage.draw(in: bounds) }
        else { super.drawText(in: rect) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            renderingTask?.cancel()
            requestKey = nil
        } else { setNeedsLayout() }
    }
}

/// The copied attributed string and its font/layout attributes remain immutable.
private struct TextInkRequest: @unchecked Sendable {
    let text: NSAttributedString
    let size: CGSize
    let scale: CGFloat
    let key: NSString

    init(text: NSAttributedString, size: CGSize, scale: CGFloat) {
        self.text = text.copy() as! NSAttributedString
        self.scale = max(1, scale)
        self.size = CGSize(width: ceil(size.width * self.scale) / self.scale,
                           height: ceil(size.height * self.scale) / self.scale)
        key = "pen:\(text):\(self.size.width):\(self.size.height):\(self.scale)" as NSString
    }
}

private actor TextInkRenderer {
    static let shared = TextInkRenderer()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 24 * 1_024 * 1_024
        return cache
    }()

    func image(for request: TextInkRequest) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: request.key) { return image }
        let image = autoreleasepool { render(request) }
        guard !Task.isCancelled else { return nil }
        cache.setObject(image, forKey: request.key,
                        cost: Int(request.size.width * request.size.height * request.scale * request.scale) * 4)
        return image
    }

    private func render(_ request: TextInkRequest) -> UIImage {
        let bounds = CGRect(origin: .zero, size: request.size)
        let framesetter = CTFramesetterCreateWithAttributedString(request.text)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: bounds, transform: nil), nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var strokes: [PKStroke] = []
        var glyphOutlines: [CGPath] = []

        for (lineIndex, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                let width = max(0.18, min(0.55, CTFontGetSize(font) * 0.007))

                for index in 0..<count {
                    guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                        tx: origins[lineIndex].x + positions[index].x,
                        ty: bounds.height - origins[lineIndex].y - positions[index].y)
                    guard let outline = glyph.copy(using: &transform) else { continue }
                    glyphOutlines.append(outline)
                    let phase = CGFloat(glyphs[index]) * 0.71
                    for contour in contours(of: outline) {
                        let path = PKStrokePath(bezierPath: contour, creationDate: Date(timeIntervalSince1970: 0)) { point in
                            let t = CGFloat(point.index) / CGFloat(max(1, point.pointCount - 1))
                            let strokeWidth = width * (0.9 + 0.1 * sin(t * .pi * 4 + phase))
                            return PKStrokePoint(location: point.location, timeOffset: Double(t) * 0.5,
                                size: CGSize(width: strokeWidth, height: strokeWidth), opacity: 1,
                                force: 1, azimuth: 0, altitude: .pi / 2)
                        }
                        strokes.append(PKStroke(ink: PKInk(.pen, color: .black), path: path,
                                                randomSeed: UInt32(glyphs[index])))
                    }
                }
            }
        }

        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = PKDrawing(strokes: strokes).image(from: bounds, scale: request.scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: request.size, format: format).image { context in
            ink?.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: bounds)
            // Fill after the ink to keep lettering continuous and opaque black.
            // Core Text also preserves fallback fonts without vector glyph paths.
            context.cgContext.saveGState()
            context.cgContext.textMatrix = .identity
            context.cgContext.translateBy(x: 0, y: bounds.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            CTFrameDraw(frame, context.cgContext)
            context.cgContext.restoreGState()
            context.cgContext.setFillColor(UIColor.black.cgColor)
            for outline in glyphOutlines {
                context.cgContext.addPath(outline)
                context.cgContext.fillPath()
            }
        }
    }

    private func contours(of path: CGPath) -> [CGPath] {
        var result: [CGPath] = []
        var current: CGMutablePath?
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                if let current { result.append(current) }
                current = CGMutablePath()
                current?.move(to: element.points[0])
            case .addLineToPoint: current?.addLine(to: element.points[0])
            case .addQuadCurveToPoint: current?.addQuadCurve(to: element.points[1], control: element.points[0])
            case .addCurveToPoint:
                current?.addCurve(to: element.points[2], control1: element.points[0], control2: element.points[1])
            case .closeSubpath: current?.closeSubpath()
            @unknown default: break
            }
        }
        if let current { result.append(current) }
        return result
    }
}
