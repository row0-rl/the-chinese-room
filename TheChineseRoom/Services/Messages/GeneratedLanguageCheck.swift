import Foundation
import NaturalLanguage

/// A conservative English-leakage signal, not a semantic language guarantee.
/// Script alone is never grounds for rejection (names, Han characters, etc.).
enum GeneratedLanguageCheck {
    /// One initial response plus at most one repair; invalid data never escapes.
    static func validated<Value>(generate: (String?) async throws -> Value,
                                 validate: (Value) -> String?) async throws -> Value? {
        let first = try await generate(nil)
        guard let issue = validate(first) else { return first }
        let repair = try await generate(issue)
        return validate(repair) == nil ? repair : nil
    }

    static func issue(in text: String, expected: LanguageProfile, field: String, userInput: String?) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "\(field) is empty."
        }

        // Only quoted content actually present in learner input is exempt. Merely
        // putting an unwanted English explanation in quotes must not bypass checks.
        var candidate = text
        let quotes = #"["“「『]([^"”」』]+)["”」』]"#
        for match in matches(quotes, in: userInput ?? "") {
            if let range = Range(match.range(at: 1), in: userInput ?? "") {
                let quoted = String((userInput ?? "")[range])
                candidate = candidate.replacingOccurrences(of: quoted, with: " ")
            }
        }
        // Flag recognisable Korean predicate endings, not Hangul itself:
        // Korean names, acronyms and shared Han characters remain permissible.
        if !expected.localeIdentifier.hasPrefix("ko") {
            for match in matches("[가-힣]+", in: candidate) {
                guard let range = Range(match.range, in: candidate) else { continue }
                let word = String(candidate[range])
                if word.count >= 3, koreanPredicateEndings.contains(where: { word.hasSuffix($0) }) {
                    return "\(field) contains a Korean predicate; write the sentence in \(expected.promptName)."
                }
            }
        }
        guard !expected.localeIdentifier.hasPrefix("en") else { return nil }
        let asianSource = expected.localeIdentifier.hasPrefix("zh") || expected.localeIdentifier.hasPrefix("ko")
        for match in matches(#"[A-Za-z]+(?:[ '’-]+[A-Za-z]+)*"#, in: candidate) {
            guard let range = Range(match.range, in: candidate) else { continue }
            let run = String(candidate[range])
            let words = run.split { !$0.isLetter }.map(String.init)
            // Preserve acronyms, camel-case brands, and proper-name phrases.
            let ordinary = words.filter { $0 == $0.lowercased() || $0 == "I" }
            guard !ordinary.isEmpty else { continue }
            if words.count == 1 {
                // Single-word language identification is too uncertain in general.
                // Only a narrow set of common leaked English glosses is flagged.
                if asianSource, ordinary[0].count >= 3, commonGlosses.contains(ordinary[0].lowercased()) {
                    return "\(field) contains an English gloss; write it in \(expected.promptName)."
                }
                continue
            }
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(run)
            let hypotheses = recognizer.languageHypotheses(withMaximum: 4)
            let expectedLanguage: NLLanguage = expected.localeIdentifier.hasPrefix("fr") ? .french :
                (expected.localeIdentifier.hasPrefix("ko") ? .korean : .simplifiedChinese)
            if hypotheses[.english, default: 0] >= 0.90,
               hypotheses[expectedLanguage, default: 0] < 0.10,
               ordinary.contains(where: { commonGlosses.contains($0.lowercased()) }) {
                return "\(field) contains likely English prose; write it in \(expected.promptName)."
            }
        }
        return nil
    }

    private static let koreanPredicateEndings = ["했다", "였다", "었다", "았다", "합니다", "해요", "어요", "아요", "렸다"]

    private static let commonGlosses: Set<String> = [
        "i", "am", "is", "are", "was", "were", "the", "a", "an", "my", "your", "their",
        "have", "has", "hungry", "hunger", "thirsty", "want", "need", "not", "very", "please",
        "with", "without", "would", "should", "cannot", "hello", "goodbye", "tense", "particle"
    ]

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
