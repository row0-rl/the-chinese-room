import Foundation

enum JapaneseRomajiNotation {
    static func units(
        text: String,
        pronunciation: [JapanesePronunciationUnit]?
    ) -> [PronunciationUnit] {
        if let pronunciation, pronunciation.map(\.surface).joined() == text {
            return alignedUnits(pronunciation)
        }
        return fallbackUnits(text: text)
    }

    private static func alignedUnits(_ pronunciation: [JapanesePronunciationUnit]) -> [PronunciationUnit] {
        var cursor = 0
        var result: [PronunciationUnit] = []
        for unit in pronunciation {
            let length = (unit.surface as NSString).length
            let range = NSRange(location: cursor, length: length)
            let reading = particleReading(for: unit) ?? unit.katakanaReading
            let notation = reading.isEmpty ? nil : HepburnRomanizer.convert(reading)
            result.append(PronunciationUnit(
                range: range,
                text: unit.surface,
                needsNotation: notation != nil,
                notation: notation
            ))
            cursor += length
        }
        return result
    }

    private static func particleReading(for unit: JapanesePronunciationUnit) -> String? {
        guard unit.isParticle else { return nil }
        let orthographic = katakana(unit.surface)
        guard orthographic == unit.katakanaReading else { return nil }
        return String(orthographic.map { character in
            switch character {
            case "ハ": return "ワ"
            case "ヘ": return "エ"
            case "ヲ": return "オ"
            default: return character
            }
        })
    }

    private static func katakana(_ source: String) -> String {
        String(String.UnicodeScalarView(source.unicodeScalars.map { scalar in
            if (0x3041...0x3096).contains(scalar.value) {
                return UnicodeScalar(scalar.value + 0x60)!
            }
            return scalar
        }))
    }
    private static func fallbackUnits(text: String) -> [PronunciationUnit] {
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: #"[\p{Hiragana}\p{Katakana}]+|\X"#)
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            let value = source.substring(with: match.range)
            let needsNotation = containsJapanese(value)
            return PronunciationUnit(
                range: match.range,
                text: value,
                needsNotation: needsNotation,
                notation: needsNotation ? HepburnRomanizer.convert(value) : nil
            )
        }
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.range(
            of: #"[\p{Hiragana}\p{Katakana}\p{Ideographic}]"#,
            options: .regularExpression
        ) != nil
    }
}

enum HepburnRomanizer {
    private static let syllables: [String: String] = [
        "ア": "a", "イ": "i", "ウ": "u", "エ": "e", "オ": "o",
        "カ": "ka", "キ": "ki", "ク": "ku", "ケ": "ke", "コ": "ko",
        "ガ": "ga", "ギ": "gi", "グ": "gu", "ゲ": "ge", "ゴ": "go",
        "サ": "sa", "シ": "shi", "ス": "su", "セ": "se", "ソ": "so",
        "ザ": "za", "ジ": "ji", "ズ": "zu", "ゼ": "ze", "ゾ": "zo",
        "タ": "ta", "チ": "chi", "ツ": "tsu", "テ": "te", "ト": "to",
        "ダ": "da", "ヂ": "ji", "ヅ": "zu", "デ": "de", "ド": "do",
        "ナ": "na", "ニ": "ni", "ヌ": "nu", "ネ": "ne", "ノ": "no",
        "ハ": "ha", "ヒ": "hi", "フ": "fu", "ヘ": "he", "ホ": "ho",
        "バ": "ba", "ビ": "bi", "ブ": "bu", "ベ": "be", "ボ": "bo",
        "パ": "pa", "ピ": "pi", "プ": "pu", "ペ": "pe", "ポ": "po",
        "マ": "ma", "ミ": "mi", "ム": "mu", "メ": "me", "モ": "mo",
        "ヤ": "ya", "ユ": "yu", "ヨ": "yo",
        "ラ": "ra", "リ": "ri", "ル": "ru", "レ": "re", "ロ": "ro",
        "ワ": "wa", "ヰ": "i", "ヱ": "e", "ヲ": "o", "ン": "n",
        "ヴ": "vu", "ヷ": "va", "ヸ": "vi", "ヹ": "ve", "ヺ": "vo",
        "ァ": "a", "ィ": "i", "ゥ": "u", "ェ": "e", "ォ": "o",
        "ヵ": "ka", "ヶ": "ke"
    ]

    private static let combinations: [String: String] = [
        "キャ": "kya", "キュ": "kyu", "キョ": "kyo",
        "ギャ": "gya", "ギュ": "gyu", "ギョ": "gyo",
        "シャ": "sha", "シュ": "shu", "ショ": "sho",
        "ジャ": "ja", "ジュ": "ju", "ジョ": "jo",
        "チャ": "cha", "チュ": "chu", "チョ": "cho",
        "ニャ": "nya", "ニュ": "nyu", "ニョ": "nyo",
        "ヒャ": "hya", "ヒュ": "hyu", "ヒョ": "hyo",
        "ビャ": "bya", "ビュ": "byu", "ビョ": "byo",
        "ピャ": "pya", "ピュ": "pyu", "ピョ": "pyo",
        "ミャ": "mya", "ミュ": "myu", "ミョ": "myo",
        "リャ": "rya", "リュ": "ryu", "リョ": "ryo",
        "イェ": "ye", "ウィ": "wi", "ウェ": "we", "ウォ": "wo",
        "ヴァ": "va", "ヴィ": "vi", "ヴェ": "ve", "ヴォ": "vo", "ヴュ": "vyu",
        "シェ": "she", "ジェ": "je", "チェ": "che",
        "ティ": "ti", "トゥ": "tu", "ディ": "di", "ドゥ": "du",
        "ツァ": "tsa", "ツィ": "tsi", "ツェ": "tse", "ツォ": "tso",
        "ファ": "fa", "フィ": "fi", "フェ": "fe", "フォ": "fo", "フュ": "fyu",
        "クァ": "kwa", "クィ": "kwi", "クェ": "kwe", "クォ": "kwo",
        "グァ": "gwa", "グィ": "gwi", "グェ": "gwe", "グォ": "gwo"
    ]

    static func convert(_ source: String) -> String? {
        let kana = Array(katakana(source))
        guard !kana.isEmpty else { return nil }
        var pieces: [String] = []
        var geminate = false
        var index = 0

        while index < kana.count {
            let character = kana[index]
            if character == "ッ" {
                geminate = true
                index += 1
                continue
            }
            if character == "ー" {
                guard !pieces.isEmpty else { return nil }
                pieces[pieces.count - 1] = lengthenLastVowel(in: pieces.last!)
                index += 1
                continue
            }

            let pair = index + 1 < kana.count ? String([character, kana[index + 1]]) : ""
            var roman: String?
            if let combined = combinations[pair] {
                roman = combined
                index += 2
            } else if character == "ン" {
                let next = nextRomanSyllable(kana, after: index)
                roman = next?.first.map { "aeiouy".contains($0) } == true ? "n'" : "n"
                index += 1
            } else if let basic = syllables[String(character)] {
                roman = basic
                index += 1
            } else if character.isWhitespace || character.isPunctuation || character.isNumber {
                roman = String(character)
                index += 1
            } else {
                return nil
            }

            if var roman {
                if geminate, let first = roman.first, !"aeioun".contains(first) {
                    roman = (roman.hasPrefix("ch") ? "t" : String(first)) + roman
                }
                geminate = false
                pieces.append(roman)
            }
        }
        guard !geminate else { return nil }
        return collapseLongVowels(pieces.joined())
    }

    private static func katakana(_ source: String) -> String {
        String(String.UnicodeScalarView(source.unicodeScalars.map { scalar in
            if (0x3041...0x3096).contains(scalar.value) {
                return UnicodeScalar(scalar.value + 0x60)!
            }
            return scalar
        }))
    }

    private static func nextRomanSyllable(_ kana: [Character], after index: Int) -> String? {
        guard index + 1 < kana.count else { return nil }
        if index + 2 < kana.count, let combined = combinations[String([kana[index + 1], kana[index + 2]])] {
            return combined
        }
        return syllables[String(kana[index + 1])]
    }

    private static func lengthenLastVowel(in value: String) -> String {
        guard let index = value.lastIndex(where: { "aeiouāēīōū".contains($0) }) else { return value }
        let replacement: Character
        switch value[index] {
        case "a", "ā": replacement = "ā"
        case "e", "ē": replacement = "ē"
        case "i", "ī": replacement = "ī"
        case "o", "ō": replacement = "ō"
        default: replacement = "ū"
        }
        var result = value
        result.replaceSubrange(index...index, with: String(replacement))
        return result
    }

    private static func collapseLongVowels(_ value: String) -> String {
        value
            .replacingOccurrences(of: "ou", with: "ō")
            .replacingOccurrences(of: "oo", with: "ō")
            .replacingOccurrences(of: "uu", with: "ū")
    }
}
