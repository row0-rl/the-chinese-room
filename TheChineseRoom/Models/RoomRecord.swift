import Foundation
import SwiftData

/// Room identity is the directional language pair, shared with its message session.
@Model
final class RoomRecord {
    @Attribute(.unique) var modeID: String
    var customName: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var createdAt: Date
    var lastUsedAt: Date

    init(mode: LanguageMode, lastUsedAt: Date = Date()) {
        self.modeID = mode.id
        self.createdAt = lastUsedAt
        self.lastUsedAt = lastUsedAt
    }

    var languageMode: LanguageMode? { LanguageCatalog.mode(id: modeID) }

    func pairLabel(strings: AppStrings) -> String {
        guard let mode = languageMode else { return modeID }
        return "\(strings.roomProfileLabel(mode.source)) → \(strings.roomProfileLabel(mode.target))"
    }

    func title(strings: AppStrings) -> String { customName ?? pairLabel(strings: strings) }
}
