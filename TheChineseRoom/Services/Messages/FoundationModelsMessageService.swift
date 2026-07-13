import Foundation
import FoundationModels

struct FoundationModelsMessageService: MessageService {
    private let model: SystemLanguageModel
    private let onTranslationReady: ((String) async -> Void)?

    init(
        model: SystemLanguageModel = .default,
        onTranslationReady: ((String) async -> Void)? = nil
    ) {
        self.model = model
        self.onTranslationReady = onTranslationReady
    }

    func randomMessage(
        after currentMessage: LearningMessage?,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage {
        try await generateMessage(
            mode: .random,
            userInput: nil,
            languageMode: languageMode,
            recentMessages: recentMessages
        )
    }

    func message(for input: String, languageMode: LanguageMode) async throws -> LearningMessage {
        try await generateMessage(mode: .userInput, userInput: input, languageMode: languageMode, recentMessages: [])
    }

    private func generateMessage(
        mode: MessageGenerationMode,
        userInput: String?,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage {
        try ensureModelIsAvailable()

        let translationSession = LanguageModelSession(model: model, instructions: MessageGenerationPrompt.instructions)
        let translationResponse = try await translationSession.respond(
            to: MessageGenerationPrompt.userPrompt(
                mode: mode,
                userInput: userInput,
                languageMode: languageMode,
                recentMessages: recentMessages
            ),
            generating: GeneratedTranslation.self
        )
        let translation = translationResponse.content

        if let onTranslationReady {
            Task { await onTranslationReady(translation.targetText) }
        }

        let alignment = try await generateValidAlignment(translation: translation, languageMode: languageMode)
        let examples = translation.examples?.map {
            MessageExample(sourceText: $0.sourceText, targetText: $0.targetText)
        }
        let literalChunks = alignment.literalChunks.map {
            MessageLiteralChunk(targetText: $0.targetText, literalText: $0.literalText)
        }

        return LearningMessage(
            sourceText: userInput ?? translation.sourceText,
            normalizedSourceText: translation.sourceText,
            targetText: translation.targetText,
            literalMeaning: literalChunks.map(\.literalText).joined(separator: " "),
            literalChunks: literalChunks,
            examples: examples
        )
    }

    private func generateValidAlignment(
        translation: GeneratedTranslation,
        languageMode: LanguageMode
    ) async throws -> GeneratedAlignment {
        let first = try await generateAlignment(
            translation: translation,
            languageMode: languageMode,
            validationError: nil
        )
        guard let validationError = alignmentValidationError(first, targetText: translation.targetText) else {
            return first
        }

        let retry = try await generateAlignment(
            translation: translation,
            languageMode: languageMode,
            validationError: validationError
        )
        guard alignmentValidationError(retry, targetText: translation.targetText) != nil else {
            return retry
        }

        return GeneratedAlignment(literalChunks: [
            GeneratedLiteralChunk(
                targetText: translation.targetText,
                literalText: retry.literalChunks.map(\.literalText).joined(separator: " ")
            )
        ])
    }

    private func generateAlignment(
        translation: GeneratedTranslation,
        languageMode: LanguageMode,
        validationError: String?
    ) async throws -> GeneratedAlignment {
        let session = LanguageModelSession(model: model, instructions: MessageGenerationPrompt.instructions)
        return try await session.respond(
            to: MessageGenerationPrompt.alignmentPrompt(
                targetText: translation.targetText,
                languageMode: languageMode,
                validationError: validationError
            ),
            generating: GeneratedAlignment.self
        ).content
    }

    private func alignmentValidationError(_ alignment: GeneratedAlignment, targetText: String) -> String? {
        guard !alignment.literalChunks.isEmpty else { return "literalChunks is empty." }
        let chunks = alignment.literalChunks.map(\.targetText)
        let normalizedTarget = normalizedAlignmentText(targetText)
        let reconstructions = [chunks.joined(), chunks.joined(separator: " ")].map(normalizedAlignmentText)
        guard reconstructions.contains(normalizedTarget) else {
            return "The chunks do not reconstruct the target expression exactly."
        }
        return nil
    }

    private func normalizedAlignmentText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([?.!,;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ensureModelIsAvailable() throws {
        guard case .available = model.availability else {
            throw FoundationModelsServiceError.unavailable(model.availability)
        }
    }
}

@Generable(description: "A corrected source expression and its natural target-language translation.")
struct GeneratedTranslation {
    @Guide(description: "The corrected, natural expression in the source language.")
    let sourceText: String

    @Guide(description: "A natural translation in the target language.")
    let targetText: String

    @Guide(description: "Exactly two short, distinct usage examples when useful; otherwise omit them.", .count(2))
    let examples: [GeneratedExample]?
}

@Generable
struct GeneratedExample {
    @Guide(description: "A natural example sentence in the source language.")
    let sourceText: String

    @Guide(description: "A natural translation of the example in the target language.")
    let targetText: String
}

@Generable(description: "A complete ordered literal alignment of a target-language expression.")
struct GeneratedAlignment {
    @Guide(description: "Ordered chunks covering the complete target expression.", .minimumCount(1))
    let literalChunks: [GeneratedLiteralChunk]
}

@Generable
struct GeneratedLiteralChunk {
    @Guide(description: "An exact target-language chunk copied from the expression, preserving order and punctuation.")
    let targetText: String

    @Guide(description: "The direct word-by-word source-language counterpart.")
    let literalText: String
}

enum FoundationModelsServiceError: LocalizedError {
    case unavailable(SystemLanguageModel.Availability)

    var errorDescription: String? {
        switch self {
        case .unavailable(.unavailable(.deviceNotEligible)):
            "On-device language generation is not supported on this iPhone."
        case .unavailable(.unavailable(.appleIntelligenceNotEnabled)):
            "Turn on Apple Intelligence in Settings to generate messages."
        case .unavailable(.unavailable(.modelNotReady)):
            "The on-device language model is still downloading. Try again later."
        case .unavailable:
            "The on-device language model is unavailable."
        }
    }
}
