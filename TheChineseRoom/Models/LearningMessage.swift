import Foundation

struct LearningMessage: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let normalizedSourceText: String
    let targetText: String
    let literalMeaning: String
    let literalChunks: [MessageLiteralChunk]
    let examples: [MessageExample]?
    var audioState: MessageAudioState

    init(
        id: UUID = UUID(),
        sourceText: String,
        normalizedSourceText: String,
        targetText: String,
        literalMeaning: String,
        literalChunks: [MessageLiteralChunk]? = nil,
        examples: [MessageExample]? = nil,
        audioState: MessageAudioState = .notLoaded
    ) {
        self.id = id
        self.sourceText = sourceText
        self.normalizedSourceText = normalizedSourceText
        self.targetText = targetText
        self.literalMeaning = literalMeaning
        self.literalChunks = literalChunks ?? [MessageLiteralChunk(targetText: targetText, literalText: literalMeaning)]
        self.examples = examples
        self.audioState = audioState
    }
}

struct MessageLiteralChunk: Identifiable, Equatable {
    let id = UUID()
    let targetText: String
    let literalText: String
}

struct MessageExample: Identifiable, Equatable {
    let id = UUID()
    let sourceText: String
    let targetText: String
}

enum MessageAudioState: Equatable {
    case notLoaded
    case loading
    case ready
    case failed(String)
}

struct LanguageProfile: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let displayName: String
    let nativeName: String
    let promptName: String

    var schemaKey: String {
        let words = displayName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let first = words.first?.lowercased() else {
            return displayName.lowercased()
        }

        return words.dropFirst().reduce(first) { partialResult, word in
            partialResult + word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
    }

    var normalizedSchemaKey: String {
        "normalized" + schemaKey.prefix(1).uppercased() + schemaKey.dropFirst()
    }

    var literalSchemaKey: String {
        "literal" + schemaKey.prefix(1).uppercased() + schemaKey.dropFirst()
    }
}

struct LanguageMode: Identifiable, Codable, Equatable {
    let source: LanguageProfile
    let target: LanguageProfile

    var id: String {
        "\(source.id)__to__\(target.id)"
    }

    var displayName: String {
        "\(source.displayName) -> \(target.displayName)"
    }

    static let defaultMode = LanguageMode(
        source: LanguageCatalog.englishUS,
        target: LanguageCatalog.frenchFrance
    )
}

enum LanguageCatalog {
    static let englishUS = LanguageProfile(
        id: "english_us",
        displayName: "English",
        nativeName: "English",
        promptName: "US English"
    )

    static let frenchFrance = LanguageProfile(
        id: "french_france",
        displayName: "French",
        nativeName: "Français",
        promptName: "French as used in France"
    )

    static let simplifiedChinese = LanguageProfile(
        id: "simplified_chinese",
        displayName: "Chinese",
        nativeName: "简体中文",
        promptName: "Simplified Chinese"
    )

    static let koreanHangul = LanguageProfile(
        id: "korean_hangul",
        displayName: "Korean",
        nativeName: "한국어",
        promptName: "Korean Hangul"
    )

    static let supportedLanguages = [
        englishUS,
        frenchFrance,
        simplifiedChinese,
        koreanHangul
    ]

    static func language(id: String) -> LanguageProfile? {
        supportedLanguages.first { $0.id == id }
    }

    static func mode(id: String) -> LanguageMode? {
        let parts = id.components(separatedBy: "__to__")
        guard parts.count == 2,
              let source = language(id: parts[0]),
              let target = language(id: parts[1])
        else {
            return nil
        }

        return LanguageMode(source: source, target: target)
    }
}

enum LanguageModeStorage {
    private static let currentModeIDKey = "current_language_mode_id"

    static var currentMode: LanguageMode? {
        guard let modeID = UserDefaults.standard.string(forKey: currentModeIDKey) else {
            return nil
        }

        return LanguageCatalog.mode(id: modeID)
    }

    static func save(_ mode: LanguageMode) {
        UserDefaults.standard.set(mode.id, forKey: currentModeIDKey)
    }
}

struct AppLocale: Equatable {
    let id: String
    let strings: AppStrings

    static let english = AppLocale(
        id: "english_us",
        strings: AppStrings(
            examplesTitle: "Examples",
            languageSelectorTitle: "Languages",
            originalLanguageTitle: "Original language",
            targetLanguageTitle: "Target language",
            doneButtonTitle: "Done",
            cancelButtonTitle: "Cancel",
            firstLaunchTitle: "Choose languages",
            firstLaunchSubtitle: "Select the language you know and the language you want to learn.",
            continueButtonTitle: "Continue",
            loadingMessageLabel: "Loading message"
        )
    )
}

struct AppStrings: Equatable {
    let examplesTitle: String
    let languageSelectorTitle: String
    let originalLanguageTitle: String
    let targetLanguageTitle: String
    let doneButtonTitle: String
    let cancelButtonTitle: String
    let firstLaunchTitle: String
    let firstLaunchSubtitle: String
    let continueButtonTitle: String
    let loadingMessageLabel: String
}
