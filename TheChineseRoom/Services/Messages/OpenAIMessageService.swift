import Foundation

struct OpenAIMessageService: MessageService {
    struct Configuration {
        let apiKey: String
        let model: String
    }

    private let configuration: Configuration
    private let session: URLSession
    private let onTranslationReady: ((String) async -> Void)?
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    init(
        configuration: Configuration,
        session: URLSession = .shared,
        onTranslationReady: ((String) async -> Void)? = nil
    ) {
        self.configuration = configuration
        self.session = session
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
        let translationOutput = try await responseOutputText(
            input: MessageGenerationPrompt.userPrompt(
                mode: mode,
                userInput: userInput,
                languageMode: languageMode,
                recentMessages: recentMessages
            ),
            format: MessageGenerationPrompt.translationResponseFormat(languageMode: languageMode)
        )

        #if DEBUG
        print("Generated translation JSON:\n\(translationOutput)")
        #endif

        let translation = try TranslationPayload.decode(from: Data(translationOutput.utf8), languageMode: languageMode)
        if let onTranslationReady {
            Task { await onTranslationReady(translation.targetText) }
        }

        let alignment = try await generateValidAlignment(translation: translation, languageMode: languageMode)
        let payload = LearningMessagePayload(translation: translation, alignment: alignment)
        let message = payload.learningMessage(originalInput: userInput)

        #if DEBUG
        print("Decoded literal chunks:\n\(message.literalChunks.map { "\($0.targetText) => \($0.literalText)" }.joined(separator: "\n"))")
        #endif

        return message
    }

    private func generateValidAlignment(
        translation: TranslationPayload,
        languageMode: LanguageMode
    ) async throws -> AlignmentPayload {
        let firstAlignment = try await generateAlignment(
            translation: translation,
            languageMode: languageMode,
            validationError: nil
        )

        if let validationError = alignmentValidationError(firstAlignment, targetText: translation.targetText) {
            #if DEBUG
            print("Alignment validation failed:\n\(validationError)")
            #endif

            let retryAlignment = try await generateAlignment(
                translation: translation,
                languageMode: languageMode,
                validationError: validationError
            )

            if let retryValidationError = alignmentValidationError(retryAlignment, targetText: translation.targetText) {
                #if DEBUG
                print("Alignment retry validation failed:\n\(retryValidationError)\nFalling back to one full-target chunk.")
                #endif

                return AlignmentPayload(
                    literalChunks: [
                        AlignmentPayload.LiteralChunkPayload(
                            targetText: translation.targetText,
                            literalText: retryAlignment.literalChunks.map(\.literalText).joined(separator: " ")
                        )
                    ]
                )
            }

            return retryAlignment
        }

        return firstAlignment
    }

    private func generateAlignment(
        translation: TranslationPayload,
        languageMode: LanguageMode,
        validationError: String?
    ) async throws -> AlignmentPayload {
        let alignmentOutput = try await responseOutputText(
            input: MessageGenerationPrompt.alignmentPrompt(
                translation: translation,
                languageMode: languageMode,
                validationError: validationError
            ),
            format: MessageGenerationPrompt.alignmentResponseFormat(languageMode: languageMode)
        )

        #if DEBUG
        print("Generated alignment JSON:\n\(alignmentOutput)")
        #endif

        return try AlignmentPayload.decode(from: Data(alignmentOutput.utf8), languageMode: languageMode)
    }

    private func alignmentValidationError(_ alignment: AlignmentPayload, targetText: String) -> String? {
        guard !alignment.literalChunks.isEmpty else {
            return "literalChunks is empty."
        }

        let targetChunks = alignment.literalChunks.map(\.targetText)
        let directReconstruction = targetChunks.joined()
        let spacedReconstruction = targetChunks.joined(separator: " ")
        let normalizedTarget = normalizedAlignmentText(targetText)
        let validReconstructions = [
            normalizedAlignmentText(directReconstruction),
            normalizedAlignmentText(spacedReconstruction)
        ]

        guard validReconstructions.contains(normalizedTarget) else {
            return "literalChunks target text reconstructs '\(directReconstruction)', expected '\(targetText)'."
        }

        return nil
    }

    private func normalizedAlignmentText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([?.!,;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func responseOutputText(
        input: String,
        format: OpenAITextFormat
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONEncoder().encode(
            OpenAIResponseRequest(
                model: configuration.model,
                instructions: MessageGenerationPrompt.instructions,
                input: input,
                text: .init(format: format),
                store: false
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIMessageServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAIMessageServiceError.apiError(statusCode: httpResponse.statusCode, message: apiErrorMessage(from: data))
        }

        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard openAIResponse.status == "completed" else {
            #if DEBUG
            print(
                """
                OpenAI message response incomplete.
                status: \(openAIResponse.status)
                incomplete reason: \(openAIResponse.incompleteDetails?.reason ?? "nil")
                error code: \(openAIResponse.error?.code ?? "nil")
                error message: \(openAIResponse.error?.message ?? "nil")
                raw response: \(String(data: data, encoding: .utf8) ?? "<non-utf8 response>")
                """
            )
            #endif
            throw OpenAIMessageServiceError.incompleteResponse
        }
        guard let outputText = openAIResponse.outputText else {
            #if DEBUG
            print(
                """
                OpenAI message response missing output_text.
                status: \(openAIResponse.status)
                raw response: \(String(data: data, encoding: .utf8) ?? "<non-utf8 response>")
                """
            )
            #endif
            throw OpenAIMessageServiceError.missingOutput
        }

        return outputText
    }

    private func apiErrorMessage(from data: Data) -> String? {
        try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data).error.message
    }
}

private enum OpenAIMessageServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String?)
    case incompleteResponse
    case missingOutput

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OpenAI returned an invalid response."
        case .apiError(let statusCode, let message):
            message ?? "OpenAI request failed with status \(statusCode)."
        case .incompleteResponse:
            "OpenAI did not complete the message."
        case .missingOutput:
            "OpenAI response did not include message content."
        }
    }
}
