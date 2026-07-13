import Foundation

@MainActor
protocol DictationService {
    var onTranscriptChange: ((String) -> Void)? { get set }

    func startRecording(localeIdentifier: String) async throws
    func finishRecording() async throws -> String
    func cancelRecording()
}

struct UnavailableDictationService: DictationService {
    var onTranscriptChange: ((String) -> Void)?

    func startRecording(localeIdentifier: String) async throws {
        throw DictationServiceError.notConfigured
    }

    func finishRecording() async throws -> String {
        throw DictationServiceError.notConfigured
    }

    func cancelRecording() {
    }
}

enum DictationServiceError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "On-device dictation is unavailable."
        }
    }
}
