import Foundation
import SwiftUI

extension Color {
    static let chineseRoomBackground = Color(red: 0.91, green: 0.86, blue: 0.75)
}

extension Bundle {
    func trimmedInfoValue(forKey key: String) -> String? {
        guard let value = object(forInfoDictionaryKey: key) as? String else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("$(") else {
            return nil
        }
        return trimmedValue
    }
}

extension ProcessInfo {
    func trimmedEnvironmentValue(forKey key: String) -> String? {
        guard let value = environment[key] else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }
        return trimmedValue
    }
}
