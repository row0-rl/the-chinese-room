import Foundation
import CoreGraphics

/// Room-qualified identity keeps equal expression IDs in separate histories distinct.
struct SavedMessageItem: Identifiable, Hashable {
    let modeID: String
    let roomTitle: String
    let message: LearningMessage
    var id: String { "\(modeID):\(message.id.uuidString)" }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum SavedMessageCollection {
    static func items(modeID: String, messages: [LearningMessage], roomTitle: String) -> [SavedMessageItem] {
        // Only the active Room's live history is eligible for this collection.
        messages.reversed().filter(\.isSaved).map {
            SavedMessageItem(modeID: modeID, roomTitle: roomTitle, message: $0)
        }
    }
}

/// Layout and hit testing use the same row positions, including the space
/// inserted beneath the single expanded card.
struct SavedMessageStackLayout {
    static let cardHeight: CGFloat = 176
    static let stride: CGFloat = 48
    static let topInset: CGFloat = 14
    static let fingerEdgeInset: CGFloat = 28
    let count: Int
    let expandedIndex: Int?
    let expandedHeight: CGFloat
    let cardHeights: [CGFloat]
    let anchorOffset: CGFloat?

    init(count: Int, expandedIndex: Int?, expandedHeight: CGFloat,
         cardHeights: [CGFloat] = [], anchorOffset: CGFloat? = nil) {
        self.count = count
        self.expandedIndex = expandedIndex
        self.expandedHeight = expandedHeight
        self.cardHeights = cardHeights
        self.anchorOffset = anchorOffset
    }

    // Each sheet has its full, immutable height even while covered. Popping
    // changes the spacing between sheets, never their text layout or size.
    func height(at index: Int) -> CGFloat {
        let measured = cardHeights.indices.contains(index) ? cardHeights[index]
            : (index == expandedIndex ? expandedHeight : Self.cardHeight)
        return max(Self.cardHeight, measured)
    }

    var topOffset: CGFloat {
        guard let expandedIndex, let anchorOffset else { return 0 }
        return anchorOffset - CGFloat(expandedIndex) * Self.stride
    }

    func advance(at index: Int) -> CGFloat {
        if index == count - 1 { return height(at: index) }
        return index == expandedIndex ? height(at: index) - Self.topInset : Self.stride
    }

    func offset(at index: Int) -> CGFloat {
        topOffset + CGFloat(index) * Self.stride + ((expandedIndex.map { $0 < index } ?? false)
            ? height(at: expandedIndex!) - Self.topInset - Self.stride : 0)
    }

    var height: CGFloat { count > 0 ? offset(at: count - 1) + self.height(at: count - 1) : 0 }

    func selectionAnchor(at index: Int, verticalDelta: CGFloat, fingerY: CGFloat? = nil) -> CGFloat {
        if verticalDelta > 0, let fingerY {
            return fingerY + Self.fingerEdgeInset - height(at: index)
        }
        if verticalDelta < 0, let fingerY {
            return fingerY - Self.fingerEdgeInset - Self.topInset
        }
        return offset(at: index)
    }

    func index(at y: CGFloat, visibleEdges: [CGFloat]? = nil) -> Int? {
        guard count > 0 else { return nil }
        let edges = visibleEdges?.count == count ? visibleEdges! : (0..<count).map { offset(at: $0) + Self.topInset }
        let bottom = edges[count - 1] - Self.topInset + self.height(at: count - 1)
        guard y >= edges[0], y < bottom else { return nil }
        // Later sheets cover earlier ones. Use measured edges when supplied,
        // so a spring's intermediate positions agree with what is on screen.
        return edges.indices.last { edges[$0] <= y }
    }
}

/// One deliberate movement selects one neighbor, regardless of paper geometry.
struct SavedMessageScrub {
    static let threshold: CGFloat = 48
    private var travel: CGFloat = 0

    mutating func selection(after delta: CGFloat, current: Int, count: Int) -> Int? {
        guard delta != 0, count > 0 else { return nil }
        // Reversing direction starts a fresh threshold immediately.
        if travel * delta < 0 { travel = 0 }
        travel += delta
        guard abs(travel) >= Self.threshold else { return nil }
        let direction = travel > 0 ? 1 : -1
        travel = 0
        let next = current + direction
        guard (0..<count).contains(next) else { return nil }
        return next
    }
}
