struct MockMessageService: MessageService {
    static let openingMessage = LearningMessage(
        sourceText: "I am hungry.",
        normalizedSourceText: "I am hungry.",
        targetText: "J'ai faim.",
        literalMeaning: "I have hunger.",
        examples: [
            MessageExample(sourceText: "I am hungry after class.", targetText: "J'ai faim apres le cours."),
            MessageExample(sourceText: "Are you hungry?", targetText: "Tu as faim ?")
        ]
    )

    private static let randomMessages = [
        LearningMessage(
            sourceText: "Let's go for a walk.",
            normalizedSourceText: "Let's go for a walk.",
            targetText: "Allons nous promener.",
            literalMeaning: "Let us go to walk ourselves.",
            examples: [
                MessageExample(sourceText: "Let's go for a walk before dinner.", targetText: "Allons nous promener avant le diner."),
                MessageExample(sourceText: "Do you want to go for a walk?", targetText: "Tu veux aller te promener ?")
            ]
        ),
        LearningMessage(
            sourceText: "I forgot my keys.",
            normalizedSourceText: "I forgot my keys.",
            targetText: "J'ai oublie mes cles.",
            literalMeaning: "I have forgotten my keys.",
            examples: [
                MessageExample(sourceText: "I forgot my keys at home.", targetText: "J'ai oublie mes cles a la maison."),
                MessageExample(sourceText: "She forgot her keys again.", targetText: "Elle a encore oublie ses cles.")
            ]
        ),
        LearningMessage(
            sourceText: "That sounds good.",
            normalizedSourceText: "That sounds good.",
            targetText: "Ca a l'air bien.",
            literalMeaning: "That has the air good.",
            examples: [
                MessageExample(sourceText: "That sounds good to me.", targetText: "Ca me parait bien."),
                MessageExample(sourceText: "Your plan sounds good.", targetText: "Ton plan a l'air bien.")
            ]
        )
    ]

    private static var submittedMessage: LearningMessage {
        LearningMessage(
            sourceText: "Me be hungry",
            normalizedSourceText: "I am hungry.",
            targetText: "J'ai faim.",
            literalMeaning: "I have hunger.",
            examples: [
                MessageExample(sourceText: "I am hungry now.", targetText: "J'ai faim maintenant."),
                MessageExample(sourceText: "I am not hungry.", targetText: "Je n'ai pas faim.")
            ]
        )
    }

    func randomMessage(
        after currentMessage: LearningMessage?,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage {
        let currentID = currentMessage?.id
        return Self.randomMessages.first { $0.id != currentID } ?? Self.openingMessage
    }

    func message(for input: String, languageMode: LanguageMode) async throws -> LearningMessage {
        LearningMessage(
            sourceText: input,
            normalizedSourceText: Self.submittedMessage.normalizedSourceText,
            targetText: Self.submittedMessage.targetText,
            literalMeaning: Self.submittedMessage.literalMeaning,
            examples: Self.submittedMessage.examples
        )
    }
}
