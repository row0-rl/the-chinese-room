import Foundation

enum IPANotation {
    private static let readingPattern = try! NSRegularExpression(
        pattern: #"^[a-zæçðøħŋœɐ-ʯʰ-˿ᴀ-ᶿ\p{M} .‿]+$"#
    )
    static func spans(_ text: String) -> [String] {
        let source = text as NSString
        let regex = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*|\X"#)
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map {
            source.substring(with: $0.range)
        }
    }

    static func needsReading(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }

    /// Only validates the response shape, not its linguistic correctness.
    static func normalizedReading(_ response: String) -> String? {
        var value = response.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if (value.hasPrefix("/") && value.hasSuffix("/")) ||
           (value.hasPrefix("[") && value.hasSuffix("]")) {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let decomposed = value.decomposedStringWithCanonicalMapping
        guard !value.isEmpty, value.count <= 160,
              readingPattern.firstMatch(in: decomposed, range: NSRange(location: 0, length: (decomposed as NSString).length)) != nil,
              value.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return nil }
        return value.precomposedStringWithCanonicalMapping
    }

    static func units(text: String, pronunciation: [IPAPronunciationUnit]?) -> [PronunciationUnit] {
        let aligned = pronunciation.flatMap { $0.map(\.surface).joined() == text ? $0 : nil }
        let units = aligned ?? spans(text).map { IPAPronunciationUnit(surface: $0, ipa: "") }
        var offset = 0
        return units.map { unit in
            let range = NSRange(location: offset, length: (unit.surface as NSString).length)
            offset += range.length
            let reading = normalizedReading(unit.ipa)
            return PronunciationUnit(
                range: range, text: unit.surface, needsNotation: needsReading(unit.surface),
                notation: reading.map { "/\($0)/" }
            )
        }
    }
}
