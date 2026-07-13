enum MessageGenerationMode {
    case random
    case userInput
}

struct MessageGenerationPrompt {
    static let instructions = """
    You generate compact language-learning cards for The Chinese Room.
    Return only the requested structured data. Include examples only when they add useful context.
    If the expression is already a complete, natural sentence and examples would mostly repeat it, set examples to null.
    When examples are present, they must be natural, short, distinct from each other, useful in daily life, and must not simply repeat the main expression.
    """

    static func userPrompt(
        mode: MessageGenerationMode,
        userInput: String?,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) -> String {
        switch mode {
        case .random:
            let recentSourceExpressions = recentMessages
                .map(\.normalizedSourceText)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let historyInstruction: String
            if recentSourceExpressions.isEmpty {
                historyInstruction = ""
            } else {
                historyInstruction = """

                Recent \(languageMode.source.promptName) expressions already shown:
                \(recentSourceExpressions.map { "- \($0)" }.joined(separator: "\n"))
                Generate a different expression. Do not repeat or closely paraphrase these expressions.
                """
            }

            return """
            Generate one useful everyday \(languageMode.source.promptName) expression for a language learner.
            Translate it naturally into \(languageMode.target.promptName).
            \(historyInstruction)
            """
        case .userInput:
            return """
            Generate a learning message from this learner input.
            Raw learner input: \(userInput ?? "")
            Interpret and correct the input as a natural \(languageMode.source.promptName) expression.
            Translate the corrected expression naturally into \(languageMode.target.promptName).
            """
        }
    }

    static func alignmentPrompt(
        targetText: String,
        languageMode: LanguageMode,
        validationError: String? = nil
    ) -> String {
        let validationInstruction = validationError.map {
            "\nPrevious alignment failed validation: \($0)\nReturn chunks that reconstruct the provided \(languageMode.target.schemaKey) exactly."
        } ?? ""

        return """
        Create a literal chunk-by-chunk translation map for this \(languageMode.target.promptName) expression.
        Work in meaning units, not whole-sentence translation.
        Choose each chunk so that:
        - the \(languageMode.target.promptName) chunk is copied exactly from the expression
        - the \(languageMode.source.promptName) chunk is its direct literal counterpart
        - chunks are small enough to help a learner see how the expression is built
        - grammar particles, endings, auxiliaries, or fixed expressions stay attached only when separating them would make the counterpart confusing
        The chunks together must cover the full \(languageMode.target.promptName) expression in order.
        \(languageMode.target.promptName): \(targetText)
        \(validationInstruction)
        """
    }
}
