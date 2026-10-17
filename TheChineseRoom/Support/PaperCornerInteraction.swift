import Foundation
import CoreGraphics

/// Diagonal corner movement is independent of the feed's vertical movement.
enum PaperCornerInteraction {
    static let hitSize: CGFloat = 76
    static let savedFoldSize: CGFloat = 48
    static let maximumFoldSize: CGFloat = 160
    static var maximumProgress: CGFloat { maximumFoldSize / savedFoldSize }
    static let travel: CGFloat = 72

    static func progress(isSaved: Bool, translation: CGSize) -> CGFloat {
        let diagonal = (translation.height - translation.width) / sqrt(2)
        return min(maximumProgress, max(0, (isSaved ? 1 : 0) + diagonal / travel))
    }

    static func displacement(foldSize: CGFloat, translation: CGSize) -> CGSize {
        let size = min(maximumFoldSize, max(0, foldSize))
        let tangent = (translation.width + translation.height) * 0.35
        let offset = min(size * 0.4, max(-size * 0.4, tangent))
        return CGSize(width: -size * 0.7 + offset, height: size * 0.7 + offset)
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
