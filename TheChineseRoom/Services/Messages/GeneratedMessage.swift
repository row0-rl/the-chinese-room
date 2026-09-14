import Foundation
import FoundationModels

enum GeneratedMessageValidation {
    static func translationIssue(_ translation: GeneratedTranslation, languageMode: LanguageMode, userInput: String?) -> String? {
        var fields: [(String, String, LanguageProfile)] = [
            ("sourceText", translation.sourceText, languageMode.source),
            ("targetText", translation.targetText, languageMode.target)
        ]
        for (index, example) in (translation.examples ?? []).enumerated() {
            fields.append(("examples[\(index)].sourceText", example.sourceText, languageMode.source))
            fields.append(("examples[\(index)].targetText", example.targetText, languageMode.target))
        }
        let languageIssue = fields.compactMap { field, text, language in
            GeneratedLanguageCheck.issue(in: text, expected: language, field: field, userInput: userInput)
        }.first
        if let languageIssue { return languageIssue }
        if let examples = translation.examples, examples.count != 2 {
            return "examples must contain exactly two entries or be omitted."
        }
        return nil
    }

    /// Match content without punctuation, then keep the original target's
    /// formatting for display. Only boundary whitespace may be inferred.
    static func restoringTargetFormatting(_ alignment: GeneratedAlignment, targetText: String) -> GeneratedAlignment {
        var cursor = targetText.startIndex
        var restored: [GeneratedLiteralChunk] = []
        for chunk in alignment.literalChunks {
            let content = withoutPunctuation(chunk.targetText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return alignment }
            let start = cursor
            while cursor < targetText.endIndex,
                  targetText[cursor].isWhitespace || targetText[cursor].isPunctuation {
                cursor = targetText.index(after: cursor)
            }
            for character in content {
                while cursor < targetText.endIndex, targetText[cursor].isPunctuation {
                    cursor = targetText.index(after: cursor)
                }
                guard cursor < targetText.endIndex, character == targetText[cursor] else { return alignment }
                cursor = targetText.index(after: cursor)
            }
            restored.append(GeneratedLiteralChunk(
                targetText: String(targetText[start..<cursor]), literalText: chunk.literalText
            ))
        }
        guard !restored.isEmpty,
              targetText[cursor...].allSatisfy({ $0.isWhitespace || $0.isPunctuation }) else { return alignment }
        if cursor != targetText.endIndex, let last = restored.popLast() {
            restored.append(GeneratedLiteralChunk(targetText: last.targetText + targetText[cursor...], literalText: last.literalText))
        }
        return GeneratedAlignment(literalChunks: restored)
    }

    private static func withoutPunctuation(_ text: String) -> String {
        text.filter { !$0.isPunctuation }
    }

    static func alignmentValidationError(_ alignment: GeneratedAlignment, targetText: String, languageMode: LanguageMode, userInput: String?) -> String? {
        guard !alignment.literalChunks.isEmpty else { return "literalChunks is empty." }
        for (index, chunk) in alignment.literalChunks.enumerated() {
            guard !chunk.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "literalChunks[\(index)].targetText is empty."
            }
            guard chunk.literalText.count <= 80 else {
                return "literalChunks[\(index)].literalText is too long. Return only a short literal translation, without definitions or grammar notes."
            }
            if let issue = GeneratedLanguageCheck.issue(in: chunk.literalText, expected: languageMode.source,
                                                       field: "literalChunks[\(index)].literalText", userInput: userInput) {
                return issue
            }
        }
        return segmentationValidationError(alignment.literalChunks.map(\.targetText), targetText: targetText)
    }

    static func segmentationValidationError(_ chunks: [String], targetText: String) -> String? {
        guard !chunks.isEmpty else { return "No chunks were returned." }
        guard chunks.allSatisfy({ !withoutPunctuation($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return "Each chunk must contain meaningful text, not just punctuation or whitespace."
        }
        let actual = withoutPunctuation(chunks.joined())
        let expected = withoutPunctuation(targetText)
        guard actual == expected else {
            // Diagnose omitted spans without treating changed/extra text as an
            // omission. This is repair feedback only, never automatic insertion.
            let compactTarget = expected.filter { !$0.isWhitespace }
            var cursor = compactTarget.startIndex
            var missing: [String] = []
            var ordered = true
            for chunk in chunks {
                let content = withoutPunctuation(chunk).filter { !$0.isWhitespace }
                guard !content.isEmpty, let range = compactTarget.range(of: content, range: cursor..<compactTarget.endIndex) else {
                    ordered = false
                    break
                }
                if range.lowerBound != cursor { missing.append(String(compactTarget[cursor..<range.lowerBound])) }
                cursor = range.upperBound
            }
            if ordered {
                if cursor != compactTarget.endIndex { missing.append(String(compactTarget[cursor...])) }
                if !missing.isEmpty {
                    return "Missing text: \(missing.joined(separator: ", ")). Insert every missing part in its original position. Return the complete corrected chunk list, including unchanged chunks."
                }
            }
            let shared = actual.commonPrefix(with: expected)
            return "Chunks must cover all words exactly once in order, ignoring punctuation. Expected text from the first mismatch: \(String(expected.dropFirst(shared.count).prefix(100))). Returned text from that point: \(String(actual.dropFirst(shared.count).prefix(100)))."
        }
        return nil
    }

    static func glossValidationError(_ text: String, language: LanguageProfile, userInput: String?) -> String? {
        guard text.count <= 80 else { return "Return only a short literal translation of at most 80 characters, without definitions or grammar notes." }
        return GeneratedLanguageCheck.issue(in: text, expected: language, field: "literalText", userInput: userInput)
    }


}

@Generable(description: "A corrected source expression and its natural target-language translation.")
struct GeneratedTranslation {
    @Guide(description: "The corrected expression in the source language assigned by this request, not the language of schema instructions.")
    let sourceText: String

    @Guide(description: "A natural translation only in the target language assigned by this request.")
    let targetText: String

    @Guide(description: "Exactly two short, distinct usage examples when useful; otherwise omit them.", .count(2))
    let examples: [GeneratedExample]?
}

@Generable
struct GeneratedExample {
    @Guide(description: "An example only in the source language assigned by this request.")
    let sourceText: String

    @Guide(description: "An example translation only in the target language assigned by this request.")
    let targetText: String
}

@Generable(description: "A complete ordered literal alignment of a target-language expression.")
struct GeneratedAlignment {
    @Guide(description: "The smallest independently explainable chunks, in target order. Prefer separate meaningful words or grammatical parts over whole phrases; cover the complete expression.", .minimumCount(1))
    let literalChunks: [GeneratedLiteralChunk]
}

@Generable
struct GeneratedLiteralChunk {
    @Guide(description: "The smallest independently explainable span copied from the target expression. Separate meaningful words and grammatical parts; combine only when splitting would distort meaning. Preserve adjacent spaces and punctuation.")
    let targetText: String

    @Guide(description: "Only the literal translation in the requested source language. No definitions, grammar notes, annotations, or commentary.")
    let literalText: String
}


@Generable(description: "An expression written only in the requested original language.")
struct GeneratedSource {
    @Guide(description: "The generated or corrected expression in the original language. Never translate it into another language.")
    let sourceText: String
}

@Generable(description: "Literal glosses for the supplied fixed chunks.")
struct GeneratedGlosses {
    @Guide(description: "Exactly one entry for each requested chunk ID. Do not merge chunks.", .minimumCount(1))
    let glosses: [GeneratedChunkGloss]
}

@Generable
struct GeneratedChunkGloss {
    @Guide(description: "The supplied chunk ID. Copy it exactly.")
    let chunkID: Int
    @Guide(description: "Only the literal translation of this chunk in the requested source language. A short word or phrase, never a definition, grammar note, or explanation. At most 80 characters.")
    let literalText: String
}
