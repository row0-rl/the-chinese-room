import FoundationModels

struct AppConfiguration {
    let languageModel: SystemLanguageModel

    static let current = AppConfiguration(languageModel: .default)
}
