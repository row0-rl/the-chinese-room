import Foundation

/// The first picker chooses a language; the second chooses one of its forms.
enum LearningLanguage: String, CaseIterable, Identifiable {
    case english = "en", french = "fr", chinese = "zh", korean = "ko"
    case spanish = "es", portuguese = "pt", italian = "it", japanese = "ja"
    case russian = "ru", hindi = "hi", swedish = "sv"

    var id: String { rawValue }

    var defaultProfile: LanguageProfile {
        switch self {
        case .english: LanguageCatalog.englishUS
        case .french: LanguageCatalog.frenchFrance
        case .chinese: LanguageCatalog.simplifiedChinese
        case .korean: LanguageCatalog.koreanHangul
        case .spanish: LanguageCatalog.spanishMexico
        case .portuguese: LanguageCatalog.portugueseBrazil
        case .italian: LanguageCatalog.italianItaly
        case .japanese: LanguageCatalog.japaneseJapan
        case .russian: LanguageCatalog.russianRussia
        case .hindi: LanguageCatalog.hindiIndia
        case .swedish: LanguageCatalog.swedishSweden
        }
    }

    var forms: [LanguageProfile] {
        [defaultProfile] + LanguageCatalog.allProfiles.filter { $0.learningLanguage == self && $0.id != defaultProfile.id }
    }

    func forms(excluding other: LanguageProfile) -> [LanguageProfile] {
        forms.filter { $0.languageIdentity != other.languageIdentity }
    }

    func defaultForm(excluding other: LanguageProfile) -> LanguageProfile? {
        forms(excluding: other).first
    }
}

extension LanguageProfile {
    /// Regions and writing systems do not turn English or Mandarin into a new language.
    var languageIdentity: String {
        Locale.Language(identifier: localeIdentifier).languageCode?.identifier ?? id
    }

    var learningLanguage: LearningLanguage {
        if languageIdentity == "yue" { return .chinese }
        return LearningLanguage(rawValue: languageIdentity) ?? .english
    }

    var usesTraditionalChinese: Bool {
        Locale.Language(identifier: localeIdentifier).script?.identifier == "Hant"
    }

    /// Apple advertises Cantonese translation using its Hong Kong Chinese locale.
    var translationLocaleIdentifier: String {
        languageIdentity == "yue" ? "zh-HK" : localeIdentifier
    }

    /// Cantonese transformations use the available Chinese writing model. This
    /// is a prompted transformation, not a claim of advertised Cantonese support.
    var modelLocaleIdentifier: String {
        guard languageIdentity == "yue" else { return localeIdentifier }
        return usesTraditionalChinese ? "zh-Hant-HK" : "zh-Hans-CN"
    }

    // Preserve existing speech engines and voices; only map Apple's Cantonese locale.
    var speechLocaleIdentifier: String {
        languageIdentity == "yue" ? "zh-HK" : localeIdentifier
    }

    var dictationLocaleIdentifier: String { speechLocaleIdentifier }

    /// Translation baselines are independent of the initial choice in the picker.
    /// Mexican Spanish still gets regional adaptation when it is the UI default.
    var needsRegionalAdaptation: Bool { !LanguageCatalog.supportedLanguages.contains { $0.id == id } }

    /// Small usage cues ground the model where a region name alone was too weak.
    /// They are examples, not substitutions or a runtime translation dictionary.
    var regionalGenerationGuidance: String {
        if languageIdentity == "yue" {
            return "Use vernacular written Cantonese, not Standard Written Chinese or Mandarin with converted characters. Use Cantonese grammar and common words such as 係, 唔, 冇, 佢, 哋 where the meaning calls for them. For taxi journeys use natural Cantonese wording such as 搭的士. Preserve the selected writing system."
        }
        switch id {
        case "english_uk":
            return "Use neutral British English with standard grammar, not phonetic accent transcription. Common vocabulary includes trainers, boot for a car's storage compartment, and lift. Preserve possessives such as my."
        case "spanish_mexico":
            return "Use Mexican vocabulary where relevant: computadora for computer, celular for mobile phone, and coche or carro for car. Use ustedes for plural you; retain the original level of politeness."
        case "spanish_chile":
            return "Use Chilean vocabulary where relevant: computador for computer, celular for mobile phone, and auto for car. Use neutral everyday Chilean Spanish; do not add po, insults, or exaggerated slang."
        default: return ""
        }
    }

    func normalizedWriting(_ text: String) -> String {
        guard learningLanguage == .chinese else { return text }
        let transform = StringTransform(rawValue: usesTraditionalChinese ? "Hans-Hant" : "Hant-Hans")
        return text.applyingTransform(transform, reverse: false) ?? text
    }
}

extension LanguageMode {
    var hasDistinctLanguages: Bool { source.languageIdentity != target.languageIdentity }

    /// Prefill a new room with general-purpose forms, retaining a valid spoken pair.
    /// For Mandarin↔Cantonese, the opposite spoken variety excludes the Mandarin
    /// default on one side, so the Cantonese side starts with Hong Kong Cantonese.
    var defaultForms: LanguageMode {
        let newSource = source.learningLanguage.defaultForm(excluding: target) ?? source.learningLanguage.defaultProfile
        let newTarget = target.learningLanguage.defaultForm(excluding: newSource)
            ?? LearningLanguage.allCases.compactMap { $0.defaultForm(excluding: newSource) }.first!
        return LanguageMode(source: newSource, target: newTarget)
    }

    /// Apple's translator rejects Mandarin↔Cantonese pairings as the same base
    /// language. Transform these expressions directly into the requested form.
    var requiresDirectChineseTransformation: Bool {
        hasDistinctLanguages && source.learningLanguage == .chinese && target.learningLanguage == .chinese
    }
}

extension LanguageCatalog {
    static let spanishMexico = LanguageProfile(id: "spanish_mexico", displayName: "Spanish",
        nativeName: "Español", promptName: "Mexican Spanish", localeIdentifier: "es-MX")

    /// Legacy IDs stay unchanged so existing Rooms, histories, and voice choices survive.
    static let allProfiles = supportedLanguages + regionalProfiles

    private static let regionalProfiles: [LanguageProfile] = [
        form("english_uk", .english, "en-GB", "British English as used in the United Kingdom"),
        form("english_australia", .english, "en-AU", "Australian English"),
        form("english_canada", .english, "en-CA", "Canadian English"),
        form("english_ireland", .english, "en-IE", "Irish English"),
        form("english_new_zealand", .english, "en-NZ", "New Zealand English"),
        form("english_india", .english, "en-IN", "Indian English"),
        form("english_singapore", .english, "en-SG", "English as used in Singapore"),
        form("english_south_africa", .english, "en-ZA", "South African English"),

        form("french_canada", .french, "fr-CA", "Québécois French as used in Québec, Canada"),
        form("french_belgium", .french, "fr-BE", "French as used in Belgium"),
        form("french_switzerland", .french, "fr-CH", "French as used in Switzerland"),
        form("french_senegal", .french, "fr-SN", "French as used in Senegal"),
        form("french_ivory_coast", .french, "fr-CI", "French as used in Côte d’Ivoire"),

        form("mandarin_taiwan", .chinese, "zh-Hant-TW", "Taiwanese Mandarin, written in Traditional Chinese using vocabulary natural in Taiwan"),
        form("mandarin_singapore", .chinese, "zh-Hans-SG", "Mandarin as used in Singapore, written in Simplified Chinese"),
        form("mandarin_malaysia", .chinese, "zh-Hans-MY", "Mandarin as used in Malaysia, written in Simplified Chinese"),
        form("cantonese_hong_kong", .chinese, "yue-Hant-HK", "Hong Kong Cantonese, written in Traditional Chinese using natural Cantonese wording, not Mandarin"),
        form("cantonese_guangdong", .chinese, "yue-Hans-CN", "Cantonese as used in Guangdong, written in Simplified Chinese using natural Cantonese wording, not Mandarin"),
        form("cantonese_macau", .chinese, "yue-Hant-MO", "Cantonese as used in Macau, written in Traditional Chinese using natural Cantonese wording, not Mandarin"),

        form("korean_north_korea", .korean, "ko-KP", "Standard North Korean (Munhwaŏ), written in Hangul using vocabulary and spelling natural in North Korea"),

        spanishMexico,
        form("spanish_chile", .spanish, "es-CL", "Chilean Spanish"),
        form("spanish_argentina", .spanish, "es-AR", "Argentine Spanish, including natural voseo where appropriate"),
        form("spanish_colombia", .spanish, "es-CO", "Colombian Spanish"),
        form("spanish_peru", .spanish, "es-PE", "Peruvian Spanish"),
        form("spanish_uruguay", .spanish, "es-UY", "Uruguayan Spanish, including natural voseo where appropriate"),
        form("spanish_venezuela", .spanish, "es-VE", "Venezuelan Spanish"),
        form("spanish_us", .spanish, "es-US", "Spanish as used in the United States"),

        form("portuguese_portugal", .portuguese, "pt-PT", "European Portuguese as used in Portugal"),
        form("portuguese_angola", .portuguese, "pt-AO", "Portuguese as used in Angola"),
        form("portuguese_mozambique", .portuguese, "pt-MZ", "Portuguese as used in Mozambique"),

        form("italian_switzerland", .italian, "it-CH", "Italian as used in Italian-speaking Switzerland"),
        form("japanese_kansai", .japanese, "ja-JP", "Kansai Japanese as used in Osaka, written in Japanese with natural Kansai wording and grammar"),
        form("russian_kazakhstan", .russian, "ru-KZ", "Russian as used in Kazakhstan"),
        form("russian_belarus", .russian, "ru-BY", "Russian as used in Belarus"),
        form("hindi_mumbai", .hindi, "hi-IN", "Colloquial Mumbai Hindi, written in Devanagari with natural local wording and grammar"),
        form("swedish_finland", .swedish, "sv-FI", "Finland Swedish (finlandssvenska), not Finnish")
    ]

    private static func form(_ id: String, _ language: LearningLanguage, _ locale: String, _ prompt: String) -> LanguageProfile {
        let base = language.defaultProfile
        let nativeName = locale.hasPrefix("yue") ? (locale.contains("Hant") ? "粵語" : "粤语") : base.nativeName
        return LanguageProfile(id: id, displayName: base.displayName, nativeName: nativeName,
            promptName: prompt, localeIdentifier: locale)
    }
}
