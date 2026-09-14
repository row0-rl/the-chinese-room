@MainActor
protocol SpeechService: AnyObject {
    var isSpeechAudioEnabled: Bool { get }
    func availableVoices(localeIdentifier: String) -> [SpeechVoice]
    func prepareSpeechAudio(_ text: String, localeIdentifier: String) async throws
    func speak(_ text: String, localeIdentifier: String, voiceIdentifier: String?) async throws
}

struct SpeechVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let qualityDescription: String
}

@MainActor
final class SilentSpeechService: SpeechService {
    var isSpeechAudioEnabled: Bool {
        false
    }

    func availableVoices(localeIdentifier: String) -> [SpeechVoice] {
        []
    }

    func prepareSpeechAudio(_ text: String, localeIdentifier: String) async throws {
    }

    func speak(_ text: String, localeIdentifier: String, voiceIdentifier: String?) async throws {
    }
}
