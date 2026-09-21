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
        let frenchText = "C’est une bonne journée."
        let french = PronunciationLayout.units(text: frenchText, system: .ipa)
        precondition(french.filter(\.needsNotation).map(\.text) == ["C’est", "une", "bonne", "journée"])
        precondition(french.map(\.text).joined() == frenchText)
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
