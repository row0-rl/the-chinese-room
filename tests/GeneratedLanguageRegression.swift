import Foundation

@main
struct GeneratedLanguageRegression {
    static func main() async throws {
        let mode = LanguageMode(source: LanguageCatalog.simplifiedChinese, target: LanguageCatalog.koreanHangul)
        func check(_ text: String, _ rejected: Bool, language: LanguageProfile = LanguageCatalog.simplifiedChinese, input: String? = nil) {
            let issue = GeneratedLanguageCheck.issue(in: text, expected: language, field: "fixture", userInput: input)
            precondition((issue != nil) == rejected, "Unexpected result for \(text): \(issue ?? "accepted")")
        }
        check("I need to be more punctual.", true)
        check("会议开始之前 기다렸다。", true)
        check("我觉得 very hungry。", true)
        check("hungry", true)
        check("I am hungry.", true, language: mode.target)
        check("我需要更准时一些。", false)
        check("회의 시작 전에 기다렸어.", false, language: mode.target)
        check("我在 Apple 工作，使用 API 2.0。", false)
        check("我的朋友叫 김민수。", false)
        check("OpenAI API 2026", false)
        check("서울 漢字 123", false, language: mode.target)
        check("保留“I am hungry”这句话。", false, input: "请保留“I am hungry”这句话。")
        check("保留“기다렸다”这个词。", false, input: "请保留“기다렸다”这个词。")
        check("English explanation: I am hungry.", true, input: "I am hungry") // Raw mixed input is not an exemption.
        check("我说“I am hungry”。", true) // Invented quotes are not exempt.
        check("I am hungry.", false, language: LanguageCatalog.englishUS)
        check("J’ai faim après le cours.", false, language: LanguageCatalog.frenchFrance)

        // Exact reported main/example content; isolate each offending field so an
        // earlier failure cannot mask a missed source-example validation.
        let badSource = GeneratedTranslation(sourceText: "I need to be more punctual.", targetText: "나는 더 정확하게 시간을 지켜야 해.", examples: nil)
        precondition(GeneratedMessageValidation.translationIssue(badSource, languageMode: mode, userInput: nil)?.contains("sourceText") == true)
        let badExample = GeneratedTranslation(sourceText: "我需要更准时一些。", targetText: badSource.targetText, examples: [
            GeneratedExample(sourceText: "考试开始迟确了。", targetText: "시험이 시작될 예정이었는데."),
            GeneratedExample(sourceText: "会议开始之前 기다렸다。", targetText: "회의 시작 전에 기다렸어.")
        ])
        precondition(GeneratedMessageValidation.translationIssue(badExample, languageMode: mode, userInput: nil)?.contains("examples[1].sourceText") == true)
        // This malformed Chinese/semantically mismatched pair is NOT proven valid
        // by a language check. Retain it as a human/on-device evaluation fixture.
        check("考试开始迟确了。", false)
        let badTargetExample = GeneratedTranslation(sourceText: "我饿了。", targetText: "배고파요.", examples: [GeneratedExample(sourceText: "我很饿。", targetText: "I am very hungry.")])
        precondition(GeneratedMessageValidation.translationIssue(badTargetExample, languageMode: mode, userInput: nil)?.contains("examples[0].targetText") == true)
        let badGloss = GeneratedAlignment(literalChunks: [GeneratedLiteralChunk(targetText: "배고파요.", literalText: "hungry")])
        precondition(GeneratedMessageValidation.alignmentValidationError(badGloss, targetText: "배고파요.", languageMode: mode, userInput: nil) != nil)
        let validGloss = GeneratedAlignment(literalChunks: [GeneratedLiteralChunk(targetText: "배고파요.", literalText: "饿（礼貌语气）")])
        precondition(GeneratedMessageValidation.alignmentValidationError(validGloss, targetText: "배고파요.", languageMode: mode, userInput: nil) == nil)
        let missingGloss = GeneratedAlignment(literalChunks: [GeneratedLiteralChunk(targetText: "배고파요.", literalText: "")])
        precondition(GeneratedMessageValidation.alignmentValidationError(missingGloss, targetText: "배고파요.", languageMode: mode, userInput: nil) != nil)
        let starter = MockMessageService.openingMessage(for: mode)
        precondition(starter.normalizedSourceText == "我饿了。" && starter.targetText == "배고파요.")
        precondition(starter.literalChunks.isEmpty)
        let exactTarget = "제가 도움이 필요합니다."
        func alignment(_ parts: [String]) -> GeneratedAlignment {
            GeneratedAlignment(literalChunks: parts.map {
                GeneratedLiteralChunk(targetText: $0, literalText: "意思")
            })
        }
        precondition(GeneratedMessageValidation.alignmentValidationError(alignment(["제가", " 도움이 필요합니다."]), targetText: exactTarget, languageMode: mode, userInput: nil) == nil)
        for parts in [["제가", "도움이 필요합니다."], ["제가 ", " 도움이 필요합니다."], ["도움이 필요합니다.", "제가 "]] {
            precondition(GeneratedMessageValidation.alignmentValidationError(alignment(parts), targetText: exactTarget, languageMode: mode, userInput: nil) != nil)
        }
        // Device regression: valid glosses must survive missing boundary spaces.
        let spaced = GeneratedMessageValidation.restoringTargetFormatting(alignment(["제가", "도움이 필요합니다."]), targetText: exactTarget)
        precondition(spaced.literalChunks.map(\.targetText).joined() == exactTarget)
        precondition(GeneratedMessageValidation.alignmentValidationError(spaced, targetText: exactTarget, languageMode: mode, userInput: nil) == nil)
        for parts in [["제가", "필요합니다."], ["도움이 필요합니다.", "제가"], ["제가", "도움이", "도움이 필요합니다."]] {
            let restored = GeneratedMessageValidation.restoringTargetFormatting(alignment(parts), targetText: exactTarget)
            precondition(GeneratedMessageValidation.alignmentValidationError(restored, targetText: exactTarget, languageMode: mode, userInput: nil) != nil)
        }
        let punctuationVariant = GeneratedMessageValidation.restoringTargetFormatting(alignment(["제가", "도움이 필요합니다。"]), targetText: exactTarget)
        precondition(punctuationVariant.literalChunks.map(\.targetText).joined() == exactTarget)
        // Device regression: AFM repaired the gloss but omitted café's final period.
        let coffeeTarget = "Allons prendre un café."
        let coffee = GeneratedAlignment(literalChunks: [
            GeneratedLiteralChunk(targetText: "Allons", literalText: "Let's (imperative, polite invitation)"),
            GeneratedLiteralChunk(targetText: "prendre", literalText: "to take"),
            GeneratedLiteralChunk(targetText: "un", literalText: "a (indefinite article)"),
            GeneratedLiteralChunk(targetText: "café", literalText: "coffee (noun)")
        ])
        let restoredCoffee = GeneratedMessageValidation.restoringTargetFormatting(coffee, targetText: coffeeTarget)
        precondition(restoredCoffee.literalChunks.map(\.targetText).joined() == coffeeTarget)
        precondition(restoredCoffee.literalChunks.map(\.literalText) == coffee.literalChunks.map(\.literalText))
        precondition(GeneratedMessageValidation.alignmentValidationError(restoredCoffee, targetText: coffeeTarget, languageMode: .defaultMode, userInput: nil) == nil)
        for ending in [".", "?", "!", "。", "？", "！", "…", "!  "] {
            let sentence = "你好" + ending
            let restored = GeneratedMessageValidation.restoringTargetFormatting(alignment(["你好"]), targetText: sentence)
            precondition(restored.literalChunks.map(\.targetText).joined() == sentence)
        }
        // Missing words must still be rejected.
        for parts in [["Allons", "prendre", "un"]] {
            let candidate = GeneratedMessageValidation.restoringTargetFormatting(alignment(parts), targetText: coffeeTarget)
            precondition(GeneratedMessageValidation.alignmentValidationError(candidate, targetText: coffeeTarget, languageMode: mode, userInput: nil) != nil)
        }
        for (target, chunks) in [
            ("Hello, world!", ["Hello", "world?"]),
            ("«Bonjour !»", ["Bonjour"]),
            ("你好，世界。", ["你好", "世界!"]),
            ("J’ai faim.", ["Jai", "faim"]),
            ("你好。", ["你", "好"])
        ] {
            let restored = GeneratedMessageValidation.restoringTargetFormatting(alignment(chunks), targetText: target)
            precondition(restored.literalChunks.map(\.targetText).joined() == target)
            precondition(GeneratedMessageValidation.alignmentValidationError(restored, targetText: target, languageMode: mode, userInput: nil) == nil)
        }
        precondition(GeneratedMessageValidation.alignmentValidationError(alignment(["你好!"]), targetText: "你好。", languageMode: mode, userInput: nil) == nil)
        // Symbols, accents and internal word spaces are still meaningful content.
        for (target, chunk) in [("café.", "cafe"), ("2+2", "22"), ("ice cream.", "icecream")] {
            let restored = GeneratedMessageValidation.restoringTargetFormatting(alignment([chunk]), targetText: target)
            precondition(GeneratedMessageValidation.alignmentValidationError(restored, targetText: target, languageMode: mode, userInput: nil) != nil)
        }
        precondition(GeneratedMessageValidation.segmentationValidationError(["C’est", "bonne", "journée"], targetText: "C’est une bonne journée.")?.contains("Missing text: une") == true)
        precondition(GeneratedMessageValidation.segmentationValidationError(["J’ai", "besoin"], targetText: "J’ai besoin d’essence.")?.contains("Missing text: dessence") == true)
        for text in ["Hello.", "Use | here.", "|¦⟦split⟧⟦split1⟧"] {
            let delimiter = MessageGenerationPrompt.segmentationDelimiter(for: text)
            precondition(!text.contains(delimiter))
        }
        let runaway = GeneratedAlignment(literalChunks: [GeneratedLiteralChunk(targetText: exactTarget, literalText: String(repeating: "主语", count: 100))])
        precondition(GeneratedMessageValidation.alignmentValidationError(runaway, targetText: exactTarget, languageMode: mode, userInput: nil) != nil)
        let alignmentPrompt = MessageGenerationPrompt.segmentationPrompt(targetText: "배고파요.", languageMode: mode)
        precondition(alignmentPrompt.contains("배고파요."))
        var attempts = 0
        let rejected: String? = try await GeneratedLanguageCheck.validated(generate: { issue in
            attempts += 1
            precondition((issue != nil) == (attempts == 2))
            return "I am hungry."
        }, validate: { GeneratedLanguageCheck.issue(in: $0, expected: mode.source, field: "sourceText", userInput: nil) })
        precondition(attempts == 2 && rejected == nil)
        attempts = 0
        let repaired: String? = try await GeneratedLanguageCheck.validated(generate: { issue in
            attempts += 1
            return issue == nil ? "I am hungry." : "我饿了。"
        }, validate: { GeneratedLanguageCheck.issue(in: $0, expected: mode.source, field: "sourceText", userInput: nil) })
        precondition(attempts == 2 && repaired == "我饿了。")
        attempts = 0
        let accepted: String? = try await GeneratedLanguageCheck.validated(generate: { _ in
            attempts += 1
            return "我饿了。"
        }, validate: { GeneratedLanguageCheck.issue(in: $0, expected: mode.source, field: "sourceText", userInput: nil) })
        precondition(attempts == 1 && accepted == "我饿了。")
        print("PASS: language-leakage regression checks, reported screenshot fields, false positives, gloss coverage and language-correct starter")
    }
}
