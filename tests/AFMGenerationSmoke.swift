import Foundation
import Darwin

@main struct AFMGenerationSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        let runtime = AppleMessageRuntime()
        let service = FoundationModelsMessageService(runtime: runtime, translator: UnusedTranslator())
        let modes = [LanguageMode.defaultMode, LanguageMode(source: LanguageCatalog.simplifiedChinese, target: LanguageCatalog.koreanHangul)]
        let blockedTarget = "Je suis en retard."
        let separator = MessageGenerationPrompt.segmentationDelimiter(for: blockedTarget)
        let raw = try await runtime.segmentText(
            to: MessageGenerationPrompt.segmentationPrompt(targetText: blockedTarget, languageMode: modes[0], delimiter: separator),
            languages: [modes[0].target]
        )
        let recovered = GeneratedMessageValidation.restoringTargetFormatting(
            GeneratedAlignment(literalChunks: raw.components(separatedBy: separator).map { GeneratedLiteralChunk(targetText: $0, literalText: "") }),
            targetText: blockedTarget
        ).literalChunks.map(\.targetText)
        if let issue = GeneratedMessageValidation.segmentationValidationError(recovered, targetText: blockedTarget) { throw SmokeError.unavailable(issue) }
        print("PASS: previously blocked sentence segmented as " + raw)
        let samples = [
            ("Where's the bathroom?", "Où est la salle de bain ?", modes[0]),
            ("I need gas.", "J'ai besoin d'essence.", modes[0]),
            ("It is a good day.", "C’est une bonne journée.", modes[0]),
            ("我需要休息一下。", "나는 좀 쉬어야 해.", modes[1])
        ]
        for (source, target, mode) in samples {
            if let message = AppleMessageRuntime.availabilityMessage(languages: [mode.source, mode.target]) { throw SmokeError.unavailable(message) }
            let result = try await service.generateValidAlignment(
                translation: GeneratedTranslation(sourceText: source, targetText: target, examples: nil),
                languageMode: mode, userInput: nil
            )
            guard let result else { throw SmokeError.unavailable("No validated breakdown for: " + target) }
            precondition(result.literalChunks.map(\.targetText).joined() == target)
            print("TARGET: \(target)\nBREAKDOWN: \(result.generatedContent.jsonString)")
        }
        print("PASS: live segmentation and glossing on French and Korean samples; linguistic accuracy requires review")
    }
}
struct UnusedTranslator: TextTranslationService {
    func translate(_ text: String, languageMode: LanguageMode) async throws -> String {
        preconditionFailure("This probe supplies fixed translations")
    }
}
enum SmokeError: Error { case unavailable(String) }
