protocol MessageService {
    func randomMessage(
        after currentMessage: LearningMessage?,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage
    func message(for input: String, languageMode: LanguageMode) async throws -> LearningMessage
    func japanesePronunciation(
        for text: String,
        languageMode: LanguageMode
    ) async -> [JapanesePronunciationUnit]?
}

extension MessageService {
    func japanesePronunciation(
        for text: String,
        languageMode: LanguageMode
    ) async -> [JapanesePronunciationUnit]? {
        nil
    }
}
