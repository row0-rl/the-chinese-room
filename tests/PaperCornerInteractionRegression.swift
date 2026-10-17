import Foundation

@main struct PaperCornerInteractionRegression {
    static func main() {
        func progress(_ saved: Bool, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
            PaperCornerInteraction.progress(isSaved: saved, translation: CGSize(width: x, height: y))
        }
        precondition(progress(false, 0, 0) == 0 && progress(true, 0, 0) == 1)
        precondition(progress(false, -18, 18) > 0 && progress(false, -18, 18) < 0.5)
        precondition(progress(false, -40, 40) >= 0.5)
        precondition(progress(true, 18, -18) < 1 && progress(true, 18, -18) > 0.5)
        precondition(progress(true, 40, -40) < 0.5)
        precondition(progress(false, 100, -100) == 0 && progress(true, -100, 100) > 1)
        precondition(progress(false, -100, 100) > 1 && progress(true, 100, -100) == 0)
        precondition(progress(false, -1000, 1000) == PaperCornerInteraction.maximumProgress)
        precondition(progress(true, -1000, 1000) == PaperCornerInteraction.maximumProgress)
        precondition(PaperCornerInteraction.maximumProgress > 3)
        precondition(progress(false, 40, 40) == 0, "Motion perpendicular to the fold must not save")
        precondition(progress(true, -40, -40) == 1)
        // The cylindrical surface meets the flat sheet with the same tangent,
        // preserves arc length, and places the corner at its requested target.
        let corner = CGPoint(x: 300, y: 0)
        for delta in [CGSize(width: -34, height: 34), CGSize(width: -55, height: 12), CGSize(width: -12, height: 55), CGSize(width: -112, height: 112)] {
            let curl = PaperCylinder(corner: corner, displacement: delta)
            let tip = curl.project(corner)
            precondition(hypot(tip.point.x - corner.x - delta.width, tip.point.y - corner.y - delta.height) < 0.00001)
            let origin = CGPoint(x: corner.x - curl.normal.dx * curl.depth, y: corner.y - curl.normal.dy * curl.depth)
            let flat = curl.project(origin)
            precondition(hypot(flat.point.x - origin.x, flat.point.y - origin.y) < 0.00001 && abs(flat.height) < 0.00001)
            let step: CGFloat = 0.001
            let next = curl.project(CGPoint(x: origin.x + curl.normal.dx * step, y: origin.y + curl.normal.dy * step))
            precondition(abs((next.point.x - flat.point.x) / step - curl.normal.dx) < 0.0001)
            precondition(abs((next.point.y - flat.point.y) / step - curl.normal.dy) < 0.0001)
            precondition(next.height / step < 0.001, "Flat-to-bend join must be tangent, not angular")
            for index in 1...100 {
                let q = CGFloat(index) / 100 * .pi * curl.radius
                let p0 = curl.project(CGPoint(x: origin.x + curl.normal.dx * (q - step), y: origin.y + curl.normal.dy * (q - step)))
                let p1 = curl.project(CGPoint(x: origin.x + curl.normal.dx * q, y: origin.y + curl.normal.dy * q))
                let length = sqrt(pow(p1.point.x - p0.point.x, 2) + pow(p1.point.y - p0.point.y, 2) + pow(p1.height - p0.height, 2))
                precondition(abs(length - step) < 0.000001, "Paper must bend without stretching")
            }
        }
        func pose(_ dy: CGFloat) -> PaperCylinder {
            let translation = CGSize(width: 0, height: dy)
            let size = PaperCornerInteraction.savedFoldSize * PaperCornerInteraction.progress(isSaved: true, translation: translation)
            return PaperCylinder(corner: .zero, displacement: PaperCornerInteraction.displacement(foldSize: size, translation: translation))
        }
        let rest = pose(0), raised = pose(-20), lowered = pose(20)
        precondition(raised.project(.zero).point.y < rest.project(.zero).point.y)
        precondition(lowered.project(.zero).point.y > rest.project(.zero).point.y)
        precondition(-raised.depth / raised.normal.dy > -rest.depth / rest.normal.dy, "Raising the tip must lower the right-edge join")
        precondition(lowered.depth / lowered.normal.dx > rest.depth / rest.normal.dx, "Lowering the tip must move the top-edge join left")
        precondition(PaperCornerInteraction.displacement(foldSize: 0, translation: CGSize(width: -50, height: 50)) == .zero)
        let frame = CGRect(x: 20, y: 150, width: 360, height: 250)
        precondition(PaperCornerInteraction.startsInCorner(CGPoint(x: 365, y: 160), paperFrame: frame))
        precondition(!PaperCornerInteraction.startsInCorner(CGPoint(x: 200, y: 160), paperFrame: frame))
        precondition(!PaperCornerInteraction.startsInCorner(CGPoint(x: 365, y: 235), paperFrame: frame))
        precondition(!PaperCornerInteraction.startsInCorner(CGPoint(x: 365, y: 140), paperFrame: frame))
        print("PASS: curl target tracking, tangent joins, surface arc length, save thresholds, and feed hit regions")
    }
}
