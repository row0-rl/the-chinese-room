import Foundation
import Darwin

/// Supplies base translations to isolate the production regional transformation.
@main struct RegionalFormsSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        let runtime = AppleMessageRuntime()
        let samples: [(String, LanguageProfile, String, String)] = [
            ("english_uk", LanguageCatalog.frenchFrance, "J’ai laissé mes baskets dans le coffre.", "I left my sneakers in the trunk."),
            ("spanish_mexico", LanguageCatalog.englishUS, "The computer is in the car.", "El ordenador está en el coche."),
            ("spanish_chile", LanguageCatalog.englishUS, "The computer is in the car.", "El ordenador está en el coche."),
            ("cantonese_hong_kong", LanguageCatalog.simplifiedChinese, "我打车去机场。", "我打车去机场。"),
            ("english_uk", LanguageCatalog.frenchFrance, "L’ascenseur de mon immeuble est en panne.", "The elevator in my apartment building is broken."),
            ("spanish_chile", LanguageCatalog.englishUS, "I left my phone at home.", "He dejado el móvil en casa."),
            ("cantonese_hong_kong", LanguageCatalog.simplifiedChinese, "我没有钱。", "我没有钱。")
        ]
        for (id, source, original, base) in samples {
            let target = LanguageCatalog.language(id: id)!
            let mode = LanguageMode(source: source, target: target)
            guard let result = try await GeneratedLanguageCheck.validated(generate: { issue in
                try await runtime.transformText(
                    to: MessageGenerationPrompt.regionalFormPrompt(text: base, originalSource: original, languageMode: mode, issue: issue),
                    languages: [target], instructions: MessageGenerationPrompt.regionalFormInstructions, greedy: true
                )
            }, validate: {
                GeneratedLanguageCheck.issue(in: $0, expected: target, field: "regionalExpression", userInput: original)
            }) else { throw FoundationModelsServiceError.languageMismatch(target) }
            print("FORM: \(id)\nBASE: \(base)\nRESULT: \(MessagePunctuation.clean(target.normalizedWriting(result)))")
        }
        print("PASS: live regional transformations returned structurally valid expressions; native-speaker review is still required")
    }
}
