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

    static func translationResponseFormat(languageMode: LanguageMode) -> OpenAITextFormat {
        let sourceName = languageMode.source.promptName
        let targetName = languageMode.target.promptName
        let sourceKey = languageMode.source.schemaKey
        let targetKey = languageMode.target.schemaKey
        let schema: [String: JSONValue] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                sourceKey: [
                    "type": "string",
                    "description": .string("A corrected, natural \(sourceName) expression.")
                ],
                targetKey: [
                    "type": "string",
                    "description": .string("A natural \(targetName) translation of \(sourceKey).")
                ],
                "examples": [
                    "type": ["array", "null"],
                    "description": "Two distinct usage examples when useful, or null when the main expression is already a complete sentence and examples would mostly repeat it.",
                    "minItems": 2,
                    "maxItems": 2,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            sourceKey: [
                                "type": "string",
                                "description": .string("A natural \(sourceName) example sentence.")
                            ],
                            targetKey: [
                                "type": "string",
                                "description": .string("A natural \(targetName) translation of \(sourceKey).")
                            ]
                        ],
                        "required": .array([.string(sourceKey), .string(targetKey)])
                    ]
                ]
            ],
            "required": .array([.string(sourceKey), .string(targetKey), .string("examples")])
        ]

        return OpenAITextFormat(
            type: "json_schema",
            name: "learning_message_translation",
            strict: true,
            schema: schema
        )
    }

    static func alignmentResponseFormat(languageMode: LanguageMode) -> OpenAITextFormat {
        let sourceName = languageMode.source.promptName
        let targetName = languageMode.target.promptName
        let sourceKey = languageMode.source.schemaKey
        let targetKey = languageMode.target.schemaKey
        let schema: [String: JSONValue] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "literalChunks": [
                    "type": "array",
                    "description": .string("Ordered \(targetName) chunks from the provided complete \(targetKey), with a corresponding word-by-word \(sourceName) translation for each chunk."),
                    "minItems": 1,
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            targetKey: [
                                "type": "string",
                                "description": .string("An exact \(targetName) chunk copied from the provided complete \(targetKey), preserving order and punctuation.")
                            ],
                            sourceKey: [
                                "type": "string",
                                "description": .string("The \(sourceName) word-by-word translation corresponding to this \(targetKey) chunk.")
                            ]
                        ],
                        "required": .array([.string(targetKey), .string(sourceKey)])
                    ]
                ]
            ],
            "required": .array([.string("literalChunks")])
        ]

        return OpenAITextFormat(
            type: "json_schema",
            name: "learning_message_alignment",
            strict: true,
            schema: schema
        )
    }

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
        translation: TranslationPayload,
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
        \(languageMode.target.promptName): \(translation.targetText)
        \(validationInstruction)
        """
    }
}
