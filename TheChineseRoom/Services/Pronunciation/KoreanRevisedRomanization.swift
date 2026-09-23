import Foundation

/// Korean Revised Romanization derived from KOROMAN's pronunciation rules.
///
/// Results are keyed by the UTF-16 offset of each original Hangul syllable so
/// the UI can keep pronunciation labels aligned with the source sentence.
struct KoreanRevisedRomanization {
    let text: String
    let characters: [Int: String]

    static func generate(text: String) -> Self? {
        var readings: [Int: String] = [:]
        var rendered = ""
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: #"[\uAC00-\uD7A3]+"#)
        var cursor = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            rendered += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let word = source.substring(with: match.range)
            guard let romanized = romanizeWord(word), romanized.count == word.count else { return nil }

            var offset = match.range.location
            for (syllable, value) in zip(word, romanized) {
                readings[offset] = value
                rendered += value
                offset += String(syllable).utf16.count
            }
            cursor = NSMaxRange(match.range)
        }
        rendered += source.substring(from: cursor)
        return Self(text: rendered, characters: readings)
    }

    private struct Syllable {
        let onset: UnicodeScalar
        let vowel: UnicodeScalar
        let coda: UnicodeScalar?
    }

    private static let onsetMap = [
        "g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s",
        "ss", "", "j", "jj", "ch", "k", "t", "p", "h"
    ]
    private static let vowelMap = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae",
        "oe", "yo", "u", "wo", "we", "wi", "yu", "eu", "ui", "i"
    ]
    private static let codaMap = [
        "", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "p", "t", "t",
        "p", "l", "m", "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"
    ]

    private static let transformations: [(String, String)] = [
        // Nasal assimilation.
        (#"[\u11b8\u11c1\u11b9\u11b2\u11b5](?=[\u1102\u1106])"#, "ᆷ"),
        (#"[\u11ae\u11c0\u11bd\u11be\u11ba\u11bb\u11c2](?=[\u1102\u1106])"#, "ᆫ"),
        (#"[\u11a8\u11a9\u11bf\u11aa\u11b0](?=[\u1102\u1106])"#, "ᆼ"),

        // Liaison and liquid assimilation.
        (#"\u11a8\u110b(?=[\u1163\u1164\u1167\u1168\u116d\u1172])"#, "ᆼᄂ"),
        (#"\u11af\u110b(?=[\u1163\u1164\u1167\u1168\u116d\u1172])"#, "ᆯᄅ"),
        (#"[\u11a8\u11bc]\u1105"#, "ᆼᄂ"),
        (#"\u11ab\u1105(?=\u1169)"#, "ᆫᄂ"),
        (#"\u11af\u1102|\u11ab\u1105"#, "ᆯᄅ"),
        (#"[\u11b7\u11b8]\u1105"#, "ᆷᄂ"),
        (#"\u11b0\u1105"#, "ᆨᄅ"),

        // Compound final consonants before a vowel.
        (#"\u11aa\u110b"#, "ᆨᄉ"), (#"\u11ac\u110b"#, "ᆫᄌ"),
        (#"\u11ad\u110b"#, "ᆫᄋ"), (#"\u11b0\u110b"#, "ᆯᄀ"),
        (#"\u11b1\u110b"#, "ᆯᄆ"), (#"\u11b2\u110b"#, "ᆯᄇ"),
        (#"\u11b3\u110b"#, "ᆯᄉ"), (#"\u11b4\u110b"#, "ᆯᄐ"),
        (#"\u11b5\u110b"#, "ᆯᄑ"), (#"\u11b6\u110b"#, "ᆯᄋ"),
        (#"\u11b9\u110b"#, "ᆸᄉ"),

        // 밟- keeps ㅂ before a consonant.
        (#"\u1107\u1161\u11b2(?=[\u1100-\u110A\u110C-\u1112])"#, "밥"),

        // Simplify compound final consonants. The cleanup rule below keeps the first.
        (#"\u11aa"#, "ᆨᆺ"), (#"\u11ac"#, "ᆫᆽ"), (#"\u11ad"#, "ᆫᇂ"),
        (#"\u11b0"#, "ᆨᆯ"), (#"\u11b1"#, "ᆷᆯ"), (#"\u11b2"#, "ᆯᆸ"),
        (#"\u11b3"#, "ᆯᆺ"), (#"\u11b4"#, "ᆯᇀ"), (#"\u11b5"#, "ᇁᆯ"),
        (#"\u11b6"#, "ᆯᇂ"), (#"\u11b9"#, "ᆸᆺ"),

        // Palatalization.
        (#"\u11ae\u110b\u1175"#, "지"),
        (#"\u11c0\u110b\u1175"#, "치"),
        (#"\u11ae\u1112\u1175"#, "치"),

        // Move a final consonant to a following silent ㅇ onset.
        (#"\u11a8\u110b"#, "ᄀ"), (#"\u11a9\u110b"#, "ᄁ"),
        (#"\u11ae\u110b"#, "ᄃ"), (#"\u11af\u110b"#, "ᄅ"),
        (#"\u11b8\u110b"#, "ᄇ"), (#"\u11ba\u110b"#, "ᄉ"),
        (#"\u11bb\u110b"#, "ᄊ"), (#"\u11bd\u110b"#, "ᄌ"),
        (#"\u11be\u110b"#, "ᄎ"), (#"\u11c2\u110b"#, "ᄋ"),

        // Aspiration with ㅎ.
        (#"\u11c2\u1100|\u11a8\u1112"#, "ᄏ"),
        (#"\u11c2\u1103|\u11ae\u1112"#, "ᄐ"),
        (#"\u11c2\u110c|\u11bd\u1112"#, "ᄎ"),
        (#"\u11c2\u1107"#, "ᄇ"), (#"\u11b8\u1112"#, "ᄑ"),

        // Remaining medial ㅎ is silent; collapse a simplified double coda.
        (#"\u11c2(?!$)"#, ""),
        (#"([\u11a8-\u11c2])([\u11a8-\u11c2])"#, "$1")
    ]

    private static func romanizeWord(_ word: String) -> [String]? {
        var scalars = Array(word.unicodeScalars)
        guard scalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) }) else { return nil }

        // Standard Pronunciation Rule 29: a final consonant before the fixed 잎
        // compound trigger inserts ㄴ (꽃잎 -> 꼰닙).
        if scalars.count >= 2, scalars.last?.value == 0xC78E {
            let previous = decompose(scalars[scalars.count - 2])
            if previous.coda != nil {
                let last = decompose(scalars[scalars.count - 1])
                scalars[scalars.count - 1] = UnicodeScalar(0xAC00 + (2 * 21 + vowelIndex(last.vowel)) * 28 + codaIndex(last.coda))!
            }
        }

        var jamo = String.UnicodeScalarView()
        for scalar in scalars {
            let syllable = decompose(scalar)
            jamo.append(syllable.onset)
            jamo.append(syllable.vowel)
            if let coda = syllable.coda { jamo.append(coda) }
        }
        var pronounced = String(jamo)
        for (pattern, replacement) in transformations {
            let regex = try! NSRegularExpression(pattern: pattern)
            pronounced = regex.stringByReplacingMatches(
                in: pronounced,
                range: NSRange(location: 0, length: (pronounced as NSString).length),
                withTemplate: replacement
            )
        }

        guard let groups = regroup(pronounced), groups.count == scalars.count else { return nil }
        return groups.enumerated().map { index, syllable in
            let onsetIndex = Int(syllable.onset.value - 0x1100)
            var onset = onsetMap[onsetIndex]
            // After liquid assimilation, an onset ㄹ is pronounced/written l.
            if onsetIndex == 5, index > 0, groups[index - 1].coda?.value == 0x11AF { onset = "l" }
            let vowel = vowelMap[vowelIndex(syllable.vowel)]
            let coda = codaMap[codaIndex(syllable.coda)]
            return onset + vowel + coda
        }
    }

    private static func decompose(_ scalar: UnicodeScalar) -> Syllable {
        let index = Int(scalar.value - 0xAC00)
        let onset = UnicodeScalar(0x1100 + index / 588)!
        let vowel = UnicodeScalar(0x1161 + (index % 588) / 28)!
        let codaValue = index % 28
        let coda = codaValue == 0 ? nil : UnicodeScalar(0x11A7 + codaValue)
        return Syllable(onset: onset, vowel: vowel, coda: coda)
    }

    private static func vowelIndex(_ scalar: UnicodeScalar) -> Int { Int(scalar.value - 0x1161) }
    private static func codaIndex(_ scalar: UnicodeScalar?) -> Int {
        scalar.map { Int($0.value - 0x11A7) } ?? 0
    }

    private static func regroup(_ jamo: String) -> [Syllable]? {
        let scalars = Array(jamo.unicodeScalars)
        var result: [Syllable] = []
        var index = 0
        while index < scalars.count {
            guard (0x1100...0x1112).contains(scalars[index].value),
                  index + 1 < scalars.count,
                  (0x1161...0x1175).contains(scalars[index + 1].value) else { return nil }
            let onset = scalars[index]
            let vowel = scalars[index + 1]
            var coda: UnicodeScalar?
            if index + 2 < scalars.count, (0x11A8...0x11C2).contains(scalars[index + 2].value) {
                coda = scalars[index + 2]
                index += 3
            } else {
                index += 2
            }
            result.append(Syllable(onset: onset, vowel: vowel, coda: coda))
        }
        return result
    }
}
