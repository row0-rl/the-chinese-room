import Foundation
import Darwin

@main struct IPAPronunciationSmoke {
    static func main() async throws {
        setbuf(stdout, nil)
        let samples: [(LanguageProfile, String, String, [String])] = [
            (LanguageCatalog.englishUS, "I am hungry.", "hungry", ["ˈhʌŋɡri", "ˈhʌŋɡɹi"]),
            (LanguageCatalog.frenchFrance, "J’ai faim.", "faim", ["fɛ̃"]),
            (LanguageCatalog.spanishSpain, "Tengo hambre.", "hambre", ["ˈambɾe", "ˈambre"]),
            (LanguageCatalog.portugueseBrazil, "Estou com fome.", "fome", ["ˈfɔmi", "ˈfɔmɪ"]),
            (LanguageCatalog.italianItaly, "Ho fame.", "fame", ["ˈfame", "ˈfaːme"]),
            (LanguageCatalog.russianRussia, "Я голоден.", "голоден", ["ˈɡolədʲɪn"]),
            (LanguageCatalog.hindiIndia, "मुझे भूख लगी है।", "भूख", ["bʱuːkʰ"]),
            (LanguageCatalog.swedishSweden, "Jag är hungrig.", "hungrig", ["ˈhɵŋːrɪɡ", "ˈhɵŋːrɪ"])
        ]
        var failures = 0
        var referenceMatches = 0
        for (language, text, qualityWord, references) in samples {
            guard let pronunciation = await AppleIPAPronunciationService.shared.pronunciation(for: text, language: language),
                  pronunciation.map(\.surface).joined() == text else {
                print("FAIL: \(language.localeIdentifier) missing result")
                failures += 1
                continue
            }
            let units = PronunciationLayout.units(text: text, system: .ipa, ipaPronunciation: pronunciation)
            guard units.map(\.text).joined() == text,
                  units.filter(\.needsNotation).allSatisfy({ $0.notation?.isEmpty == false }) else {
                print("FAIL: \(language.localeIdentifier) missing display notation")
                failures += 1
                continue
            }
            print("PASS: \(language.localeIdentifier) \(text)")
            print(units.filter(\.needsNotation).map { "\($0.text) \($0.notation!)" }.joined(separator: " | "))
            let reading = pronunciation.first { $0.surface == qualityWord }?.ipa
            if references.contains(where: { $0 == reading }) { referenceMatches += 1 }
            else { print("QUALITY REVIEW: \(qualityWord) = \(reading ?? "missing"); reference \(references.joined(separator: " or "))") }
        }
        print("Functional: \(samples.count - failures)/\(samples.count). Selected-word reference matches: \(referenceMatches)/\(samples.count) (not a complete accuracy evaluation).")
        guard failures == 0 else { throw Failure.missingReadings(failures) }
    }
    enum Failure: Error { case missingReadings(Int) }
}
