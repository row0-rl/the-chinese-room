import Foundation
import FoundationModels
import Darwin

/// Functional failures fail the smoke test. Reading accuracy is reported
/// separately until the on-device model meets the app's quality requirements.
@main struct JapanesePronunciationSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        let model = SystemLanguageModel.default
        guard model.isAvailable else { throw Failure.unavailable }
        print("On-device model context size: \(model.contextSize)")
        let samples: [(String, [String])] = [
            ("学校へ行きます。", ["ガッコウヘイキマス"]),
            ("二十歳の大学生です。", ["ハタチノダイガクセイデス"]),
            ("今日はいい天気ですね。", ["キョウハイイテンキデスネ"]),
            ("私は日本語を勉強しています。", ["ワタシハニホンゴヲベンキョウシテイマス"]),
            ("明日、東京で会いましょう。", ["アシタトウキョウデアイマショウ", "アストウキョウデアイマショウ"]),
            ("生ビールを二杯ください。", ["ナマビールヲニハイクダサイ"]),
            ("一人で映画を見ました。", ["ヒトリデエイガヲミマシタ"]),
            ("橋を渡ってください。", ["ハシヲワタッテクダサイ"]),
            ("雨が降っています。", ["アメガフッテイマス"]),
            ("三日後に戻ります。", ["ミッカゴニモドリマス"]),
            ("山田さんは銀行員です。", ["ヤマダサンハギンコウインデス"]),
            ("彼は本を読んでいる。", ["カレハホンヲヨンデイル"]),
            ("🙂 学校へ行きます！\n", ["ガッコウヘイキマス"]),
            ("コーヒーをください。", ["コーヒーヲクダサイ"])
        ]
        var failures = 0
        var qualityMatches = 0
        let service = AppleJapanesePronunciationService()
        for (text, expectedReadings) in samples {
            let start = Date()
            guard let units = await service.pronunciation(for: text),
                  units.map(\.surface).joined() == text else {
                print("FAIL: no complete source-preserving result for \(text.debugDescription)")
                failures += 1
                continue
            }
            let rendered = PronunciationLayout.units(
                text: text, system: .hepburnRomanization, japanesePronunciation: units
            )
            let japanese = rendered.filter {
                $0.text.range(of: #"[\p{Hiragana}\p{Katakana}\p{Ideographic}]"#, options: .regularExpression) != nil
            }
            guard rendered.map(\.text).joined() == text,
                  !japanese.isEmpty,
                  japanese.allSatisfy({ $0.notation?.isEmpty == false }),
                  units.filter({ !$0.katakanaReading.isEmpty }).allSatisfy({
                      $0.katakanaReading.range(of: #"^[ァ-ヺー・]+$"#, options: .regularExpression) != nil
                  }) else {
                print("FAIL: missing romanization or invalid stored kana for \(text.debugDescription)")
                failures += 1
                continue
            }
            let actual = units.map(\.katakanaReading).joined()
            let qualityMatch = expectedReadings.contains(actual)
            if qualityMatch { qualityMatches += 1 }
            print("PASS: \(text.debugDescription) (\(String(format: "%.2f", Date().timeIntervalSince(start)))s)")
            print("  Kana: \(actual)")
            print("  Romaji: \(rendered.compactMap(\.notation).joined(separator: " "))")
            if !qualityMatch { print("  QUALITY MISMATCH: expected \(expectedReadings.joined(separator: " or "))") }
        }
        print("Functional: \(samples.count - failures)/\(samples.count); reading quality: \(qualityMatches)/\(samples.count)")
        guard failures == 0 else { throw Failure.functional(failures) }
        if CommandLine.arguments.contains("--strict-quality"), qualityMatches != samples.count {
            throw Failure.quality(samples.count - qualityMatches)
        }
    }

    enum Failure: Error {
        case unavailable
        case functional(Int)
        case quality(Int)
    }
}
