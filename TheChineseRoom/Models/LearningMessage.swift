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
    let localeIdentifier: String

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
        promptName: "US English",
        localeIdentifier: "en-US"
    )

    static let frenchFrance = LanguageProfile(
        id: "french_france",
        displayName: "French",
        nativeName: "Français",
        promptName: "French as used in France",
        localeIdentifier: "fr-FR"
    )

    static let simplifiedChinese = LanguageProfile(
        id: "simplified_chinese",
        displayName: "Chinese",
        nativeName: "简体中文",
        promptName: "Simplified Chinese",
        localeIdentifier: "zh-Hans-CN"
    )

    static let koreanHangul = LanguageProfile(
        id: "korean_hangul",
        displayName: "Korean",
        nativeName: "한국어",
        promptName: "Korean Hangul",
        localeIdentifier: "ko-KR"
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

    static func speechPreview(for language: LanguageProfile) -> String {
        let examples: [String]

        switch language.id {
        case englishUS.id:
            examples = ["What a beautiful day.", "Let’s learn something new.", "It’s nice to meet you."]
        case frenchFrance.id:
            examples = ["Quelle belle journée.", "Apprenons quelque chose de nouveau.", "Ravi de vous rencontrer."]
        case simplifiedChinese.id:
            examples = ["今天天气真好。", "我们来学点新东西吧。", "很高兴认识你。"]
        case koreanHangul.id:
            examples = ["오늘 정말 좋은 날이에요.", "새로운 것을 배워 봅시다.", "만나서 반가워요."]
        default:
            examples = [language.nativeName]
        }

        return examples.randomElement() ?? language.nativeName
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

enum SpeechVoiceStorage {
    private static let keyPrefix = "speech_voice_for_mode_"

    static func voiceIdentifier(for mode: LanguageMode) -> String? {
        UserDefaults.standard.string(forKey: keyPrefix + mode.id)
    }

    static func save(_ voiceIdentifier: String?, for mode: LanguageMode) {
        let key = keyPrefix + mode.id
        if let voiceIdentifier {
            UserDefaults.standard.set(voiceIdentifier, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// The learning source controls the interface, independently of device language.
struct AppLocale: Equatable {
    let id: String
    var strings: AppStrings { AppStrings(localeIdentifier: id) }

    static let english = AppLocale(id: "en")

    static func forLanguage(_ language: LanguageProfile) -> AppLocale {
        switch language.localeIdentifier.split(separator: "-").first {
        case "fr": return AppLocale(id: "fr")
        case "zh": return AppLocale(id: "zh-Hans")
        case "ko": return AppLocale(id: "ko")
        default: return .english
        }
    }
}

/// Typed access to Apple's compiled Interface.xcstrings resources.
struct AppStrings: Equatable {
    let localeIdentifier: String

    private func text(_ key: String) -> String {
        let englishBundle = Bundle.main.path(forResource: "en", ofType: "lproj")
            .flatMap { Bundle(path: $0) } ?? .main
        let sourceBundle = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj")
            .flatMap { Bundle(path: $0) } ?? englishBundle
        let fallback = englishBundle.localizedString(forKey: key, value: nil, table: "Interface")
        return sourceBundle.localizedString(forKey: key, value: fallback, table: "Interface")
    }

    var literalUnavailable: String { text("literalUnavailable") }
    var generationLanguageFailure: String { text("generationLanguageFailure") }
    var examplesTitle: String { text("examplesTitle") }
    var languageSelectorTitle: String { text("languageSelectorTitle") }
    var originalLanguageTitle: String { text("originalLanguageTitle") }
    var targetLanguageTitle: String { text("targetLanguageTitle") }
    var doneButtonTitle: String { text("doneButtonTitle") }
    var cancelButtonTitle: String { text("cancelButtonTitle") }
    var firstLaunchTitle: String { text("firstLaunchTitle") }
    var firstLaunchSubtitle: String { text("firstLaunchSubtitle") }
    var continueButtonTitle: String { text("continueButtonTitle") }
    var nextMessageLabel: String { text("nextMessageLabel") }
    var generationInterruptedLabel: String { text("generationInterruptedLabel") }
    var loadingMessageLabel: String { text("loadingMessageLabel") }
    var settingsTitle: String { text("settingsTitle") }
    var localTitle: String { text("localTitle") }
    var localLabel: String { text("localLabel") }
    var listeningLabel: String { text("listeningLabel") }
    var inputPlaceholder: String { text("inputPlaceholder") }
    var sendLabel: String { text("sendLabel") }
    var holdToSpeakLabel: String { text("holdToSpeakLabel") }
    var keyboardLabel: String { text("keyboardLabel") }
    var playLabel: String { text("playLabel") }
    var hideLiteralLabel: String { text("hideLiteralLabel") }
    var showLiteralLabel: String { text("showLiteralLabel") }
    var learningModeTitle: String { text("learningModeTitle") }
    var voiceTitle: String { text("voiceTitle") }
    var systemDefaultTitle: String { text("systemDefaultTitle") }
    var voiceFooter: String { text("voiceFooter") }
    var enhancedVoiceTitle: String { text("enhancedVoiceTitle") }
    var defaultVoiceTitle: String { text("defaultVoiceTitle") }

    func languageName(_ language: LanguageProfile) -> String {
        Locale(identifier: localeIdentifier).localizedString(forIdentifier: language.localeIdentifier)
            ?? language.nativeName
    }
}
