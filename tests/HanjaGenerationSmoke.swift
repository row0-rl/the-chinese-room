import Foundation
import Darwin

@main struct HanjaGenerationSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        let mode = LanguageMode(source: LanguageCatalog.simplifiedChinese, target: LanguageCatalog.koreanHangul)
        if let issue = AppleMessageRuntime.availabilityMessage(languages: [mode.source, mode.target]) {
            print("UNAVAILABLE: \(issue)")
            exit(2)
        }
        let service = FoundationModelsMessageService(runtime: AppleMessageRuntime(), translator: UnusedHanjaTranslator())
        let samples: [(String, String, [String], [String])] = [
            ("去学校。", "학교에 가요.", ["학교에", " 가요."], ["학교=學校"]),
            ("在图书馆学习。", "도서관에서 공부해요.", ["도서관에서", " 공부해요."], ["도서관=圖書館", "공부=工夫"]),
            ("水很凉。", "물이 차가워요.", ["물이", " 차가워요."], []),
            ("坐公交车。", "버스를 타요.", ["버스를", " 타요."], []),
            ("吃苹果。", "사과를 먹어요.", ["사과를", " 먹어요."], ["사과=沙果"]),
            ("请接受我的道歉。", "제 사과를 받아 주세요.", ["제", " 사과를", " 받아 주세요."], ["사과=謝過"]),
            ("学校和学校。", "학교와 학교.", ["학교와", " 학교."], ["학교=學校", "학교=學校"]),
            ("学生提问。", "학생이 질문해요.", ["학생이", " 질문해요."], ["학생=學生", "질문=質問"]),
            ("去医院。", "병원에 가요.", ["병원에", " 가요."], ["병원=病院"]),
            ("今天是星期一。", "오늘은 월요일이에요.", ["오늘은", " 월요일이에요."], ["월요일=月曜日"]),
            ("猫在睡觉。", "고양이가 자요.", ["고양이가", " 자요."], []),
            ("吃披萨。", "피자를 먹어요.", ["피자를", " 먹어요."], []),
            ("时间不够。", "시간이 부족해요.", ["시간이", " 부족해요."], ["시간=時間", "부족=不足"]),
            ("谢谢。", "감사합니다.", ["감사", "합니다."], ["감사=感謝"])

        ]
        var matched = 0
        for (source, target, chunks, expected) in samples {
            let message = LearningMessage(sourceText: source, normalizedSourceText: source, targetText: target,
                literalMeaning: "", literalChunks: chunks.map { MessageLiteralChunk(targetText: $0, literalText: "") })
            let start = Date()
            let result = await service.hanjaAnnotations(for: message, languageMode: mode)
            let values = result?.map { "\($0.surface)=\($0.hanja)" }
            let matches = values == expected
            if matches { matched += 1 }
            print("\(matches ? "MATCH" : "REVIEW"): \(target) | \(values.map { String(describing: $0) } ?? "FAILED") | expected \(expected) | \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
        }
        print("Sample expectations matched: \(matched)/\(samples.count). This is a small smoke set, not a general quality benchmark.")
        if matched != samples.count { exit(1) }
    }
}
struct UnusedHanjaTranslator: TextTranslationService {
    func translate(_ text: String, languageMode: LanguageMode) async throws -> String {
        preconditionFailure("Hanja smoke samples supply fixed translations")
    }
}
