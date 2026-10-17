import Foundation
import CoreGraphics

/// Diagonal corner movement is independent of the feed's vertical movement.
enum PaperCornerInteraction {
    static let hitSize: CGFloat = 76
    static let savedFoldSize: CGFloat = 64
    static let maximumFoldSize: CGFloat = 160
    static var maximumProgress: CGFloat { maximumFoldSize / savedFoldSize }
    static let travel: CGFloat = 72

    static func progress(isSaved: Bool, translation: CGSize) -> CGFloat {
        let diagonal = (translation.height - translation.width) / sqrt(2)
        return min(maximumProgress, max(0, (isSaved ? 1 : 0) + diagonal / travel))
    }

    static func shouldToggle(isSaved: Bool, translation: CGSize) -> Bool {
        // Quadrant III in mathematical coordinates is down-left on screen.
        // Only that quadrant can save a flat corner; any drag can unsave it.
        isSaved || (translation.width < 0 && translation.height > 0)
    }

    static func displacement(foldSize: CGFloat, translation: CGSize) -> CGSize {
        let size = min(maximumFoldSize, max(0, foldSize))
        let tangent = (translation.width + translation.height) * 0.35
        let offset = min(size * 0.4, max(-size * 0.4, tangent))
        return CGSize(width: -size * 0.7 + offset, height: size * 0.7 + offset)
    }

    /// Stretch graphite along the projected edge, but retain its screen width.
    static func ribbonTransform(start: CGPoint, end: CGPoint, sourceStart: CGFloat,
                                sourceLength: CGFloat) -> CGAffineTransform? {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.00001, sourceLength > 0.00001 else { return nil }
        let a = dx / sourceLength, b = dy / sourceLength
        return CGAffineTransform(a: a, b: b, c: -dy / length, d: dx / length,
                                 tx: start.x - a * sourceStart, ty: start.y - b * sourceStart)
    }

    /// Keep the pencil silhouette within a fraction of a point while removing
    /// redundant samples along the flat edges. Curved projection subdivides
    /// retained edges separately, only where the paper is actually bending.
    static func simplifiedOutline(_ points: [CGPoint], tolerance: CGFloat = 0.12) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var kept = Set([0, points.count - 1])
        var ranges = [(0, points.count - 1)]
        while let (start, end) = ranges.popLast() {
            guard end > start + 1 else { continue }
            let a = points[start], b = points[end]
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            var largest = tolerance * tolerance
            var split: Int?
            for index in (start + 1)..<end {
                let p = points[index]
                let t = lengthSquared > 0 ? min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared)) : 0
                let ex = p.x - a.x - t * dx, ey = p.y - a.y - t * dy
                let distance = ex * ex + ey * ey
                if distance > largest { largest = distance; split = index }
            }
            if let split {
                kept.insert(split)
                ranges.append((start, split))
                ranges.append((split, end))
            }
        }
        return kept.sorted().map { points[$0] }
    }

    static func startsInCorner(_ location: CGPoint, paperFrame: CGRect) -> Bool {
        CGRect(x: paperFrame.maxX - hitSize, y: paperFrame.minY,
               width: hitSize, height: min(hitSize, paperFrame.height)).contains(location)
    }
}

/// An isometric cylindrical bend: flat sheet, circular arc, then lifted flat sheet.
/// Distances along the surface are unchanged. The projected tip is the target.
/// Geometry reference: https://github.com/harism/android-pagecurl
struct PaperCylinder {
    let corner: CGPoint
    let normal: CGVector
    let radius: CGFloat
    let depth: CGFloat

    init(corner: CGPoint, displacement: CGSize) {
        self.corner = corner
        let length = max(0.001, hypot(displacement.width, displacement.height))
        normal = CGVector(dx: -displacement.width / length, dy: -displacement.height / length)
        radius = min(14, length * 0.18)
        depth = (length + .pi * radius) / 2
    }

    func distance(_ p: CGPoint) -> CGFloat {
        (p.x - corner.x) * normal.dx + (p.y - corner.y) * normal.dy + depth
    }

    func project(_ p: CGPoint) -> (point: CGPoint, height: CGFloat, facing: CGFloat) {
        let q = distance(p)
        guard q > 0 else { return (p, 0, 1) }
        let angle = min(.pi, q / radius)
        let bent = q < .pi * radius ? radius * sin(angle) : -(q - .pi * radius)
        return (CGPoint(x: p.x + normal.dx * (bent - q),
                        y: p.y + normal.dy * (bent - q)),
                radius * (1 - cos(angle)), cos(angle))
    }

    func drawingBounds(vertices: [CGPoint], paperSize: CGSize) -> CGRect {
        let projected = vertices.map { project($0).point }
        let minX = min(0, projected.map(\.x).min() ?? 0)
        let minY = min(0, projected.map(\.y).min() ?? 0)
        let maxX = max(paperSize.width, projected.map(\.x).max() ?? paperSize.width)
        let maxY = max(paperSize.height, projected.map(\.y).max() ?? paperSize.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: -12, dy: -12)
    }

    /// Affine projection of one narrow surface band. Its two boundaries match
    /// the cylinder exactly; intermediate points approximate the circular arc.
    func bandTransform(lower: CGFloat, upper: CGFloat) -> CGAffineTransform {
        func bent(_ q: CGFloat) -> CGFloat {
            if q <= 0 { return q }
            if q >= .pi * radius { return -(q - .pi * radius) }
            return radius * sin(q / radius)
        }
        let slope = (bent(upper) - bent(lower)) / max(0.00001, upper - lower)
        let intercept = bent(lower) - slope * lower
        let k = depth - corner.x * normal.dx - corner.y * normal.dy
        let shift = (slope - 1) * k + intercept
        return CGAffineTransform(a: 1 + (slope - 1) * normal.dx * normal.dx,
                                 b: (slope - 1) * normal.dx * normal.dy,
                                 c: (slope - 1) * normal.dx * normal.dy,
                                 d: 1 + (slope - 1) * normal.dy * normal.dy,
                                 tx: normal.dx * shift, ty: normal.dy * shift)
    }

    func clip(_ polygon: [CGPoint], at value: CGFloat, above: Bool) -> [CGPoint] {
        guard var previous = polygon.last else { return [] }
        var result: [CGPoint] = []
        var previousD = distance(previous) - value
        for current in polygon {
            let d = distance(current) - value
            let inside = above ? d >= 0 : d <= 0
            let previousInside = above ? previousD >= 0 : previousD <= 0
            if inside != previousInside {
                let t = previousD / (previousD - d)
                result.append(CGPoint(x: previous.x + (current.x - previous.x) * t,
                                      y: previous.y + (current.y - previous.y) * t))
            }
            if inside { result.append(current) }
            previous = current; previousD = d
        }
        return result
    }
}
