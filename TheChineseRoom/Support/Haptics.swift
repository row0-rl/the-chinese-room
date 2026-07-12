import UIKit

@MainActor
enum Haptics {
    static func messageChanged() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func dictationStarted() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
