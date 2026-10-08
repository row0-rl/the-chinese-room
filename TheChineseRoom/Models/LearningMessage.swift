import Foundation

struct LearningMessage: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let normalizedSourceText: String
    let targetText: String
    let literalMeaning: String
    let literalChunks: [MessageLiteralChunk]
    let examples: [MessageExample]?
    var japanesePronunciation: [JapanesePronunciationUnit]?
    var ipaPronunciation: [IPAPronunciationUnit]?
    var hanjaAnnotations: [HanjaAnnotation]?
    var audioState: MessageAudioState

    init(
        id: UUID = UUID(),
        sourceText: String,
        normalizedSourceText: String,
        targetText: String,
        literalMeaning: String,
        literalChunks: [MessageLiteralChunk]? = nil,
        examples: [MessageExample]? = nil,
        japanesePronunciation: [JapanesePronunciationUnit]? = nil,
        ipaPronunciation: [IPAPronunciationUnit]? = nil,
        hanjaAnnotations: [HanjaAnnotation]? = nil,
        audioState: MessageAudioState = .notLoaded
    ) {
        self.id = id
        self.sourceText = sourceText
        self.normalizedSourceText = MessagePunctuation.clean(normalizedSourceText)
        let cleanedTarget = MessagePunctuation.clean(targetText)
        self.targetText = cleanedTarget
        self.literalMeaning = MessagePunctuation.clean(literalMeaning)
        var chunks = literalChunks ?? [MessageLiteralChunk(targetText: targetText, literalText: literalMeaning)]
        // Older saved cards already have chunks. Remove only the deleted suffix,
        // leaving every earlier chunk and annotation offset in place.
        var removed = targetText.count - cleanedTarget.count
        while removed > 0, let last = chunks.popLast() {
            let count = min(removed, last.targetText.count)
            removed -= count
            let remaining = String(last.targetText.dropLast(count))
            if !remaining.isEmpty {
                chunks.append(MessageLiteralChunk(targetText: remaining, literalText: MessagePunctuation.clean(last.literalText)))
            }
        }
        self.literalChunks = chunks
        self.examples = examples
        // Regenerate legacy readings against the cleaned target instead of
        // persisting pronunciation spans that still cover deleted punctuation.
        self.japanesePronunciation = cleanedTarget == targetText ? japanesePronunciation : nil
        self.ipaPronunciation = cleanedTarget == targetText ? ipaPronunciation : nil
        self.hanjaAnnotations = hanjaAnnotations
        self.audioState = audioState
    }
}

/// One source-preserving Japanese span and the katakana reading generated for it.
/// Katakana is persisted so Hepburn formatting remains deterministic and can
/// evolve without making another model request.
struct JapanesePronunciationUnit: Equatable {
    let surface: String
    let katakanaReading: String
    let isParticle: Bool
}

/// Ordered source spans with IPA without enclosing slashes. Formatting has an empty reading.
struct IPAPronunciationUnit: Codable, Equatable {
    let surface: String
    let ipa: String
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

    init(sourceText: String, targetText: String) {
        self.sourceText = MessagePunctuation.clean(sourceText)
        self.targetText = MessagePunctuation.clean(targetText)
    }
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

/// Available notation choices are defined independently of pronunciation generation.
enum PronunciationNotationSystem: String, Codable, CaseIterable {
    case ipa
    case pinyin
    case revisedRomanization
    case hepburnRomanization

    static func fixedSystem(for language: LanguageProfile) -> Self {
        switch language.id {
        case LanguageCatalog.simplifiedChinese.id: .pinyin
        case LanguageCatalog.koreanHangul.id: .revisedRomanization
        case LanguageCatalog.japaneseJapan.id: .hepburnRomanization
        default: .ipa
        }
    }

    var placeholder: String {
        switch self {
        case .ipa: "/…/"
        case .pinyin, .revisedRomanization, .hepburnRomanization: "…"
        }
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

    static let spanishSpain = LanguageProfile(
        id: "spanish_spain",
        displayName: "Spanish",
        nativeName: "Español",
        promptName: "Spanish as used in Spain",
        localeIdentifier: "es-ES"
    )

    static let portugueseBrazil = LanguageProfile(
        id: "portuguese_brazil",
        displayName: "Portuguese",
        nativeName: "Português",
        promptName: "Brazilian Portuguese",
        localeIdentifier: "pt-BR"
    )

    static let italianItaly = LanguageProfile(
        id: "italian_italy",
        displayName: "Italian",
        nativeName: "Italiano",
        promptName: "Italian as used in Italy",
        localeIdentifier: "it-IT"
    )

    static let japaneseJapan = LanguageProfile(
        id: "japanese_japan",
        displayName: "Japanese",
        nativeName: "日本語",
        promptName: "Japanese as used in Japan",
        localeIdentifier: "ja-JP"
    )

    static let russianRussia = LanguageProfile(
        id: "russian_russia",
        displayName: "Russian",
        nativeName: "Русский",
        promptName: "Russian as used in Russia",
        localeIdentifier: "ru-RU"
    )

    static let hindiIndia = LanguageProfile(
        id: "hindi_india",
        displayName: "Hindi",
        nativeName: "हिन्दी",
        promptName: "Hindi as used in India",
        localeIdentifier: "hi-IN"
    )

    static let swedishSweden = LanguageProfile(
        id: "swedish_sweden",
        displayName: "Swedish",
        nativeName: "Svenska",
        promptName: "Swedish as used in Sweden",
        localeIdentifier: "sv-SE"
    )

    static let supportedLanguages = [
        englishUS,
        frenchFrance,
        simplifiedChinese,
        koreanHangul,
        spanishSpain,
        portugueseBrazil,
        italianItaly,
        japaneseJapan,
        russianRussia,
        hindiIndia,
        swedishSweden
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
        case spanishSpain.id:
            examples = ["Qué día tan bonito.", "Aprendamos algo nuevo.", "Encantado de conocerte."]
        case portugueseBrazil.id:
            examples = ["Que dia lindo.", "Vamos aprender algo novo.", "Prazer em conhecer você."]
        case italianItaly.id:
            examples = ["Che bella giornata.", "Impariamo qualcosa di nuovo.", "Piacere di conoscerti."]
        case japaneseJapan.id:
            examples = ["今日はいい天気ですね。", "新しいことを学びましょう。", "お会いできてうれしいです。"]
        case russianRussia.id:
            examples = ["Какой прекрасный день.", "Давайте узнаем что-нибудь новое.", "Приятно познакомиться."]
        case hindiIndia.id:
            examples = ["आज का दिन बहुत सुंदर है।", "आइए कुछ नया सीखें।", "आपसे मिलकर खुशी हुई।"]
        case swedishSweden.id:
            examples = ["Vilken vacker dag.", "Låt oss lära oss något nytt.", "Trevligt att träffas."]
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
    var dictationStarting: String { text("dictationStarting") }
    var listeningLabel: String { text("listeningLabel") }
    var inputPlaceholder: String { text("inputPlaceholder") }
    var sendLabel: String { text("sendLabel") }
    var holdToSpeakLabel: String { text("holdToSpeakLabel") }
    var keyboardLabel: String { text("keyboardLabel") }
    var playLabel: String { text("playLabel") }
    var hideLiteralLabel: String { text("hideLiteralLabel") }
    var showLiteralLabel: String { text("showLiteralLabel") }
    var showPronunciationLabel: String { text("showPronunciationLabel") }
    var hidePronunciationLabel: String { text("hidePronunciationLabel") }
    var pronunciationTitle: String { text("pronunciationTitle") }
    var notationSystemTitle: String { text("notationSystemTitle") }
    var pronunciationPlaceholder: String { text("pronunciationPlaceholder") }
    var pronunciationUnavailable: String { text("pronunciationUnavailable") }
    var hanjaUnavailable: String { text("hanjaUnavailable") }
    var pinyinFooter: String { text("pinyinFooter") }
    var pronunciationFooter: String { text("pronunciationFooter") }

    func notationName(_ system: PronunciationNotationSystem) -> String {
        switch system {
        case .ipa: text("notationIPA")
        case .pinyin: text("notationPinyin")
        case .revisedRomanization: text("notationRomanization")
        case .hepburnRomanization: text("notationHepburn")
        }
    }

    var learningModeTitle: String { text("learningModeTitle") }
    var voiceTitle: String { text("voiceTitle") }
    var systemDefaultTitle: String { text("systemDefaultTitle") }
    var voiceFooter: String { text("voiceFooter") }
    var speechUnavailableTitle: String { text("speechUnavailableTitle") }
    var appearanceTitle: String { text("appearanceTitle") }

    func appearanceName(_ appearance: AppAppearance) -> String {
        switch appearance {
        case .system: text("appearanceSystem")
        case .light: text("appearanceLight")
        case .dark: text("appearanceDark")
        }
    }

    func languageName(_ language: LanguageProfile) -> String {
        Locale(identifier: localeIdentifier).localizedString(forIdentifier: language.localeIdentifier)
            ?? language.nativeName
    }
}

/// UTF-16 offsets refer to the exact target sentence, including repeated words.
struct HanjaAnnotation: Codable, Equatable, Identifiable {
    let offset: Int
    let surface: String
    let hanja: String
    var id: Int { offset }

    static func supports(_ mode: LanguageMode) -> Bool {
        mode.source.id == LanguageCatalog.simplifiedChinese.id &&
        mode.target.id == LanguageCatalog.koreanHangul.id
    }

    /// A mixed Hangul/Hanja sentence has an exact one-character correspondence.
    /// No whitespace normalization or guessed alignment is allowed.
    static func validated(transformation: String, text: String) -> [Self]? {
        guard transformation.count == text.count else { return nil }
        var spans: [(surface: String, hanja: String)] = []
        for (source, output) in zip(text, transformation) {
            let surface = String(source)
            let hanja = source == output ? "" : String(output)
            if let last = spans.last, last.hanja.isEmpty == hanja.isEmpty {
                spans[spans.count - 1] = (last.surface + surface, last.hanja + hanja)
            } else {
                spans.append((surface, hanja))
            }
        }
        return validated(spans: spans, text: text)
    }

    /// Complete source coverage avoids guessing which occurrence a model meant.
    /// This validates alignment and script, not the correctness of the etymology.
    static func validated(spans: [(surface: String, hanja: String)], text: String) -> [Self]? {
        guard !spans.isEmpty, spans.map(\.surface).joined() == text else { return nil }
        var result: [Self] = []
        var offset = 0
        for span in spans {
            guard !span.surface.isEmpty else { return nil }
            if !span.hanja.isEmpty {
                guard span.surface.range(of: #"^[가-힣]+$"#, options: .regularExpression) != nil,
                      span.hanja.range(of: #"^\p{Unified_Ideograph}+$"#, options: .regularExpression) != nil,
                      span.surface.count == span.hanja.count else { return nil }
                result.append(Self(offset: offset, surface: span.surface, hanja: span.hanja))
            }
            offset += span.surface.utf16.count
        }
        return result
    }
}

/// Presentation punctuation is deterministic and independent of model prompts.
enum MessagePunctuation {
    static func clean(_ text: String) -> String {
        var result = text
        while result.last?.isWhitespace == true { result.removeLast() }
        guard let ending = result.last, [".", "。", "．", "।", "۔"].contains(ending) else { return result }
        // Preserve ellipses, including repeated full stops in other scripts.
        if result.dropLast().last == ending { return result }
        if ending == "." {
            let token = result.split(whereSeparator: \.isWhitespace).last.map(String.init) ?? result
            let stem = String(token.dropLast())
            // Dotted abbreviations (U.S., e.g.), initials, and common undotted abbreviations.
            let parts = stem.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 1 && parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) }) { return result }
            if stem.count == 1 && stem.first?.isUppercase == true { return result }
            let abbreviations: Set<String> = ["mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc", "approx", "dept", "inc", "ltd", "co", "corp", "no", "fig", "vol", "г", "ул", "д", "рис", "стр"]
            if abbreviations.contains(stem.lowercased()) { return result }
        }
        result.removeLast()
        return result
    }
}
