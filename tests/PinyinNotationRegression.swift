import Foundation

@main
struct PinyinNotationRegression {
    static func main() {
        let chinese = PronunciationLayout.units(text: "中国", system: .pinyin)
        precondition(chinese.map(\.text) == ["中", "国"])
        precondition(chinese.map(\.notation) == ["zhōng", "guó"])
        let text = "🙂我喜欢 Swift 和 iOS 27。"
        let units = PronunciationLayout.units(text: text, system: .pinyin)
        precondition(units.map(\.text).joined() == text)
        precondition(units.first(where: { $0.text == "我" })?.notation == "wǒ")
        precondition(units.first(where: { $0.text == "我" })?.range.location == 2)
        precondition(units.first(where: { $0.text == "Swift" })?.needsNotation == false)
        precondition(units.last?.needsNotation == false)
        for text in ["你好，银行在哪里？", "重庆银行", "女儿去西安。", "嗯，你好！🙂"] {
            let result = ApplePinyinNotation.generate(text: text)!
            precondition(result.characters != nil)
            print("PASS: sentence-context character alignment: \(text)")
        }
        precondition(ApplePinyinNotation.generate(text: "𠮷")?.characters == nil)
        let korean = PronunciationLayout.units(text: "한국어 좋아요!", system: .revisedRomanization)
        precondition(korean.filter(\.needsNotation).map(\.text) == ["한", "국", "어", "좋", "아", "요"])
        precondition(korean.filter(\.needsNotation).map(\.notation) == ["han", "gu", "geo", "jo", "a", "yo"])
        let koreanCases: [(String, [String])] = [
            ("안녕하세요", ["an", "nyeong", "ha", "se", "yo"]),
            ("한국어", ["han", "gu", "geo"]),
            ("같이", ["ga", "chi"]),
            ("설날", ["seol", "lal"]),
            ("먹는", ["meong", "neun"]),
            ("신라", ["sil", "la"]),
            ("좋다", ["jo", "ta"]),
            ("읽어", ["il", "geo"]),
            ("닭이", ["dal", "gi"]),
            ("꽃잎", ["kkon", "nip"])
        ]
        for (source, expected) in koreanCases {
            let result = PronunciationLayout.units(text: source, system: .revisedRomanization)
            precondition(result.compactMap(\.notation) == expected, "Korean romanization mismatch: \(source)")
        }
        let mixedKorean = PronunciationLayout.units(text: "🙂 한국어!", system: .revisedRomanization)
        precondition(mixedKorean.map(\.text).joined() == "🙂 한국어!")
        precondition(mixedKorean.first(where: { $0.text == "한" })?.range.location == 3)
        let frenchText = "C’est une bonne journée."
        let french = PronunciationLayout.units(text: frenchText, system: .ipa)
        precondition(french.filter(\.needsNotation).map(\.text) == ["C’est", "une", "bonne", "journée"])
        precondition(french.map(\.text).joined() == frenchText)
        let russian = PronunciationLayout.units(text: "Добрый день!", system: .ipa)
        precondition(russian.filter(\.needsNotation).map(\.text) == ["Добрый", "день"])
        let hindi = PronunciationLayout.units(text: "नमस्ते दुनिया!", system: .ipa)
        precondition(hindi.filter(\.needsNotation).map(\.text) == ["नमस्ते", "दुनिया"])
        let swedish = PronunciationLayout.units(text: "God morgon!", system: .ipa)
        precondition(swedish.filter(\.needsNotation).map(\.text) == ["God", "morgon"])
        let japanese = PronunciationLayout.units(text: "こんにちは！", system: .hepburnRomanization)
        precondition(japanese.filter(\.needsNotation).map(\.text) == ["こんにちは"])
        precondition(japanese.compactMap(\.notation) == ["konnichiha"])
        let kanaCases = [
            "きっぷ": "kippu",
            "しんよう": "shin'yō",
            "スーパー": "sūpā",
            "パーティー": "pātī",
            "がっこう": "gakkō",
            "とうきょう": "tōkyō",
            "まっちゃ": "matcha",
            "ましょう": "mashō"
        ]
        for (source, expected) in kanaCases {
            precondition(HepburnRomanizer.convert(source) == expected, "Hepburn mismatch: \(source)")
        }
        let generatedJapanese = [
            JapanesePronunciationUnit(surface: "二十歳", katakanaReading: "ハタチ", isParticle: false),
            JapanesePronunciationUnit(surface: "の", katakanaReading: "ノ", isParticle: true),
            JapanesePronunciationUnit(surface: "大学生", katakanaReading: "ダイガクセイ", isParticle: false),
            JapanesePronunciationUnit(surface: "です", katakanaReading: "デス", isParticle: false),
            JapanesePronunciationUnit(surface: "。", katakanaReading: "", isParticle: false)
        ]
        let alignedJapanese = PronunciationLayout.units(
            text: "二十歳の大学生です。",
            system: .hepburnRomanization,
            japanesePronunciation: generatedJapanese
        )
        precondition(alignedJapanese.map(\.text) == ["二十歳", "の", "大学生", "です", "。"])
        precondition(alignedJapanese.compactMap(\.notation) == ["hatachi", "no", "daigakusei", "desu"])
        precondition(alignedJapanese.map(\.text).joined() == "二十歳の大学生です。")
        let particleJapanese = [
            JapanesePronunciationUnit(surface: "学校", katakanaReading: "ガッコウ", isParticle: false),
            JapanesePronunciationUnit(surface: "へ", katakanaReading: "ヘ", isParticle: true),
            JapanesePronunciationUnit(surface: "行きます", katakanaReading: "イキマス", isParticle: false)
        ]
        precondition(PronunciationLayout.units(
            text: "学校へ行きます",
            system: .hepburnRomanization,
            japanesePronunciation: particleJapanese
        ).compactMap(\.notation) == ["gakkō", "e", "ikimasu"])
        let compoundParticleJapanese = [
            JapanesePronunciationUnit(surface: "ここ", katakanaReading: "ココ", isParticle: false),
            JapanesePronunciationUnit(surface: "では", katakanaReading: "デハ", isParticle: true),
            JapanesePronunciationUnit(surface: "ない", katakanaReading: "ナイ", isParticle: false)
        ]
        precondition(PronunciationLayout.units(
            text: "ここではない",
            system: .hepburnRomanization,
            japanesePronunciation: compoundParticleJapanese
        ).compactMap(\.notation) == ["koko", "dewa", "nai"])
        let chunks = [MessageLiteralChunk(targetText: "中", literalText: "middle"), MessageLiteralChunk(targetText: "国", literalText: "country")]
        let groups = PronunciationLayout.groups(text: "中国", units: chinese, chunks: chunks)!
        precondition(groups.count == 2)
        precondition(groups.flatMap(\.units).map(\.notation) == ["zhōng", "guó"])
        let whole = PronunciationLayout.groups(text: "中国", units: chinese, chunks: [MessageLiteralChunk(targetText: "中国", literalText: "China")])!
        precondition(whole.count == 1 && whole[0].units.count == 2)
        let contraction = PronunciationLayout.units(text: "C’est", system: .ipa)
        let splitContraction = [MessageLiteralChunk(targetText: "C’", literalText: "this"), MessageLiteralChunk(targetText: "est", literalText: "is")]
        let merged = PronunciationLayout.groups(text: "C’est", units: contraction, chunks: splitContraction)!
        precondition(merged.count == 1 && merged[0].units.count == 1 && merged[0].chunks.count == 2)
        precondition(PronunciationLayout.groups(text: "中国", units: chinese, chunks: chunks.reversed()) == nil)
        print("PASS: character, syllable-block, word units; punctuation; UTF-16 offsets; literal grouping and word-boundary protection")
    }
}
