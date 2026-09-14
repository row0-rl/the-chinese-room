import Foundation
import FoundationModels

struct FoundationModelsMessageService: MessageService {
    private let runtime: AppleMessageRuntime
    private let translator: any TextTranslationService
    private let onTranslationReady: ((String) async -> Void)?

    init(
        runtime: AppleMessageRuntime,
        translator: any TextTranslationService,
        onTranslationReady: ((String) async -> Void)? = nil
    ) {
        self.runtime = runtime
        self.translator = translator
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

        let prompt = MessageGenerationPrompt.sourcePrompt(
            mode: mode, userInput: userInput, languageMode: languageMode, recentMessages: recentMessages
        )
        guard let source = try await GeneratedLanguageCheck.validated(generate: { issue in
            let repair = issue.map { "\nRepair the response: " + $0 } ?? ""
            return try await runtime.respond(to: prompt + repair, generating: GeneratedSource.self, languages: [languageMode.source])
        }, validate: { GeneratedLanguageCheck.issue(in: $0.sourceText, expected: languageMode.source, field: "sourceText", userInput: userInput) }) else {
            throw FoundationModelsServiceError.languageMismatch(languageMode.source)
        }

        try Task.checkCancellation()
        let targetText = try await translator.translate(source.sourceText, languageMode: languageMode)
        try Task.checkCancellation()
        let translation = GeneratedTranslation(sourceText: source.sourceText, targetText: targetText, examples: nil)

        if let onTranslationReady {
            Task { await onTranslationReady(translation.targetText) }
        }

        let alignment = try await generateValidAlignment(translation: translation, languageMode: languageMode, userInput: userInput)
        let examples = translation.examples?.map {
            MessageExample(sourceText: $0.sourceText, targetText: $0.targetText)
        }
        let literalChunks = (alignment?.literalChunks ?? []).map {
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

    func generateValidAlignment(
        translation: GeneratedTranslation,
        languageMode: LanguageMode,
        userInput: String?
    ) async throws -> GeneratedAlignment? {
        do {
            var chunks: [String]?
            var previous: String?
            var issue: String?
            let delimiter = MessageGenerationPrompt.segmentationDelimiter(for: translation.targetText)
            for _ in 0..<2 {
                try Task.checkCancellation()
                let response = try await runtime.segmentText(
                    to: MessageGenerationPrompt.segmentationPrompt(targetText: translation.targetText, languageMode: languageMode, delimiter: delimiter, previous: previous, issue: issue),
                    languages: [languageMode.target]
                )
                previous = response
                let pieces = response.components(separatedBy: delimiter)
                let formatted = GeneratedMessageValidation.restoringTargetFormatting(
                    GeneratedAlignment(literalChunks: pieces.map { GeneratedLiteralChunk(targetText: $0, literalText: "") }),
                    targetText: translation.targetText
                ).literalChunks.map(\.targetText)
                issue = GeneratedMessageValidation.segmentationValidationError(formatted, targetText: translation.targetText)
                if issue == nil { chunks = formatted; break }
                logBreakdownFailure("Segmentation rejected: " + (issue ?? ""))
            }
            guard let chunks else { return nil }

            var accepted: [Int: String] = [:]
            var requested = Array(chunks.indices)
            previous = nil
            issue = nil
            // One batch normally; one repair batch containing only invalid/missing IDs.
            for _ in 0..<2 {
                try Task.checkCancellation()
                let response = try await runtime.respond(
                    to: MessageGenerationPrompt.glossPrompt(chunks: chunks, requestedIDs: requested, targetText: translation.targetText, sourceText: translation.sourceText, languageMode: languageMode, previous: previous, issue: issue),
                    generating: GeneratedGlosses.self, languages: [languageMode.source, languageMode.target]
                )
                previous = response.generatedContent.jsonString
                var failures: [String] = []
                for id in requested {
                    let matches = response.glosses.filter { $0.chunkID == id }
                    guard matches.count == 1 else {
                        failures.append("Chunk ID \(id) needs exactly one gloss; received \(matches.count).")
                        continue
                    }
                    if let error = GeneratedMessageValidation.glossValidationError(matches[0].literalText, language: languageMode.source, userInput: userInput) {
                        failures.append("Chunk ID \(id): \(error)")
                    } else {
                        accepted[id] = matches[0].literalText
                    }
                }
                requested = chunks.indices.filter { accepted[$0] == nil }
                if requested.isEmpty {
                    return GeneratedAlignment(literalChunks: chunks.indices.map {
                        GeneratedLiteralChunk(targetText: chunks[$0], literalText: accepted[$0]!)
                    })
                }
                issue = failures.joined(separator: "\n")
                logBreakdownFailure("Glosses rejected: " + (issue ?? ""))
            }
            return nil
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw error
            }
            // Optional breakdown failures must not discard the completed translation.
            logBreakdownFailure("Breakdown generation failed: \(String(reflecting: error))")
            return nil
        }
    }

    private func logBreakdownFailure(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[TheChineseRoom] \(message)\n".utf8))
        #endif
    }
}
