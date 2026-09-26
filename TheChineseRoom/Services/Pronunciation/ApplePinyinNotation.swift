import Foundation

/// Ranges refer to the unchanged target sentence, not to literal-meaning chunks.
struct PronunciationUnit: Identifiable {
    let range: NSRange
    let text: String
    let needsNotation: Bool
    var notation: String?
    var id: Int { range.location }
}

struct PronunciationGroup: Identifiable {
    let units: [PronunciationUnit]
    let chunks: [MessageLiteralChunk]
    var id: Int { units.first?.id ?? 0 }
}

enum PronunciationLayout {
    static func units(
        text: String,
        system: PronunciationNotationSystem,
        japanesePronunciation: [JapanesePronunciationUnit]? = nil,
        ipaPronunciation: [IPAPronunciationUnit]? = nil
    ) -> [PronunciationUnit] {
        if system == .hepburnRomanization {
            return JapaneseRomajiNotation.units(text: text, pronunciation: japanesePronunciation)
        }
        if system == .ipa {
            return IPANotation.units(text: text, pronunciation: ipaPronunciation)
        }
        // IPA and Japanese word spans returned above. Chinese and Korean
        // readings align to individual grapheme clusters.
        let pattern = #"[\p{Latin}\p{M}\p{N}]+(?:['’\-][\p{Latin}\p{M}\p{N}]+)*|\X"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let source = text as NSString
        let readings: [Int: String]?
        switch system {
        case .pinyin:
            readings = ApplePinyinNotation.generate(text: text)?.characters
        case .revisedRomanization:
            readings = KoreanRevisedRomanization.generate(text: text)?.characters
        case .hepburnRomanization, .ipa:
            readings = nil
        }
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let value = source.substring(with: match.range)
            let hasHan = value.range(of: #"\p{Ideographic}"#, options: .regularExpression) != nil
            let needsNotation: Bool
            switch system {
            case .pinyin: needsNotation = hasHan
            case .revisedRomanization:
                needsNotation = value.range(of: #"\p{Hangul}"#, options: .regularExpression) != nil
            case .hepburnRomanization:
                needsNotation = value.range(
                    of: #"[\p{Hiragana}\p{Katakana}\p{Ideographic}]"#,
                    options: .regularExpression
                ) != nil
            case .ipa: needsNotation = value.contains { $0.isLetter || $0.isNumber }
            }
            return PronunciationUnit(range: match.range, text: value, needsNotation: needsNotation,
                                     notation: readings?[match.range.location])
        }
    }

    static func groups(text: String, units: [PronunciationUnit], chunks: [MessageLiteralChunk]) -> [PronunciationGroup]? {
        // Literal chunks normally retain exact source formatting. Match trimmed chunks to also
        // tolerate whitespace inferred by the alignment service, without discarding punctuation.
        let source = text as NSString
        var cursor = 0
        var ends: [Int] = []
        for chunk in chunks {
            let content = chunk.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            let range = source.range(of: content, options: [], range: NSRange(location: cursor, length: source.length - cursor))
            guard range.location != NSNotFound,
                  source.substring(with: NSRange(location: cursor, length: range.location - cursor)).allSatisfy(\.isWhitespace) else { return nil }
            cursor = NSMaxRange(range)
            ends.append(cursor)
        }
        guard !chunks.isEmpty, source.substring(from: cursor).allSatisfy(\.isWhitespace) else { return nil }
        var groups: [PronunciationGroup] = []
        var firstChunk = 0
        var firstUnit = 0
        for index in chunks.indices {
            let boundary = ends[index]
            // A literal boundary inside a word must not split its pronunciation label.
            if units.contains(where: { $0.range.location < boundary && NSMaxRange($0.range) > boundary }) { continue }
            let lastUnit = index == chunks.count - 1 ? units.count : (units.firstIndex { $0.range.location >= boundary } ?? units.count)
            groups.append(PronunciationGroup(units: Array(units[firstUnit..<lastUnit]), chunks: Array(chunks[firstChunk...index])))
            firstChunk = index + 1
            firstUnit = lastUnit
        }
        return firstChunk == chunks.count ? groups : nil
    }
}

struct ApplePinyinNotation {
    let text: String
    /// Pinyin syllables keyed by source UTF-16 character offsets. Nil means alignment failed.
    let characters: [Int: String]?

    static func generate(text: String) -> Self? {
        guard let converted = text.applyingTransform(.mandarinToLatin, reverse: false) else { return nil }
        return Self(text: converted, characters: align(converted, source: text))
    }

    private static func align(_ converted: String, source: String) -> [Int: String]? {
        var cursor = converted.startIndex
        var sourceOffset = 0
        var result: [Int: String] = [:]
        for character in source {
            let original = String(character)
            defer { sourceOffset += original.utf16.count }
            if character.isWhitespace { continue }
            while cursor < converted.endIndex, converted[cursor].isWhitespace {
                cursor = converted.index(after: cursor)
            }
            if original.range(of: #"\p{Ideographic}"#, options: .regularExpression) != nil {
                guard let syllable = converted.range(
                    of: #"[\p{Latin}\p{M}]+"#,
                    options: [.regularExpression, .anchored],
                    range: cursor..<converted.endIndex
                ) else { return nil }
                result[sourceOffset] = String(converted[syllable])
                cursor = syllable.upperBound
            } else {
                // ICU normalizes some punctuation, such as 。 to a period.
                guard let literal = original.applyingTransform(.mandarinToLatin, reverse: false),
                      converted[cursor...].hasPrefix(literal) else { return nil }
                cursor = converted.index(cursor, offsetBy: literal.count)
            }
        }
        guard converted[cursor...].allSatisfy(\.isWhitespace) else { return nil }
        return result
    }
}
