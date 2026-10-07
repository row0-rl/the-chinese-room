protocol MessageService {
    func hanjaAnnotations(for message: LearningMessage, languageMode: LanguageMode) async -> [HanjaAnnotation]?
    func ipaPronunciation(for text: String, languageMode: LanguageMode) async -> [IPAPronunciationUnit]?
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
    func hanjaAnnotations(for message: LearningMessage, languageMode: LanguageMode) async -> [HanjaAnnotation]? { nil }

    func ipaPronunciation(for text: String, languageMode: LanguageMode) async -> [IPAPronunciationUnit]? {
        nil
    }

    func japanesePronunciation(
        for text: String,
        languageMode: LanguageMode
    ) async -> [JapanesePronunciationUnit]? {
        nil
    }
}
