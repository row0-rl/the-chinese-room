// Build for an iOS Simulator with -D LAUNCH_TITLE_EXPORTER, Environment.swift,
// and the bundled Patrick Hand font registered through the fixture Info.plist.
// Outputs launch assets to the fixture's Documents directory; no runtime rasterization needed.
import CoreText
import PencilKit
import UIKit

@MainActor
enum LaunchTitleAssetRenderer {
    static let size = CGSize(width: 320, height: 80)

    static func export(to directory: URL) throws {
        let font = CTFontCreateWithName(AppFont.name as CFString, 44, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "The Chinese Room", attributes: [
            kCTFontAttributeName as NSAttributedString.Key: font
        ]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let offset = CGPoint(x: (size.width - bounds.width) / 2 - bounds.minX,
                             y: (size.height + bounds.height) / 2 + bounds.minY)
        var outlines: [CGPath] = []
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                    tx: offset.x + positions[index].x, ty: offset.y - positions[index].y)
                if let outline = glyph.copy(using: &transform) { outlines.append(outline) }
            }
        }
        let mask = CGMutablePath()
        outlines.forEach { mask.addPath($0) }
        var strokes: [PKStroke] = []
        for (glyphIndex, outline) in outlines.enumerated() {
            let rect = outline.boundingBoxOfPath.insetBy(dx: -3, dy: -3)
            for (row, y) in stride(from: rect.minY, through: rect.maxY, by: 2.0).enumerated() {
                let points = (0...Int(ceil(rect.width))).map { index in
                    let x = rect.minX + CGFloat(index)
                    let width = 1.1 + 0.15 * sin(x * 0.3 + CGFloat(row))
                    return PKStrokePoint(location: CGPoint(x: x, y: y + 0.15 * sin(x * 0.4)),
                        timeOffset: Double(index) * 0.01, size: CGSize(width: width, height: width),
                        opacity: 0.45, force: 0.5, azimuth: .pi / 6, altitude: .pi / 3)
                }
                strokes.append(PKStroke(ink: PKInk(.pencil, color: .black),
                    path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)),
                    randomSeed: UInt32(glyphIndex * 100 + row)))
            }
        }
        let drawing = PKDrawing(strokes: strokes)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for scale: CGFloat in [1, 2, 3] {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = false
            var raster: UIImage!
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                raster = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
            }
            let pencil = UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.addPath(mask)
                context.cgContext.clip()
                raster.draw(at: .zero)
            }
            for variant in ["ink", "light", "dark"] {
                let image: UIImage
                if variant == "ink" { image = pencil }
                else {
                    let traits = UITraitCollection(userInterfaceStyle: variant == "dark" ? .dark : .light)
                    image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                        pencil.withTintColor(UIColor.chineseRoomInk.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
                            .draw(at: .zero, blendMode: .normal, alpha: 0.14)
                    }
                }
                try image.pngData()!.write(to: directory.appendingPathComponent("title-\(variant)@\(Int(scale))x.png"))
            }
        }
    }
}

#if LAUNCH_TITLE_EXPORTER
import SwiftUI
@main struct LaunchTitleExporter: App {
    var body: some Scene {
        WindowGroup {
            Color.chineseRoomBackground.ignoresSafeArea().task {
                do {
                    let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    try LaunchTitleAssetRenderer.export(to: directory)
                } catch { print("Launch asset export failed: \(error)") }
            }
        }
    }
}
#endif
