@MainActor
protocol SpeechService: AnyObject {
    var isSpeechAudioEnabled: Bool { get }
    func prepareSpeechAudio(_ text: String) async throws
    func speak(_ text: String) async throws
}

@MainActor
final class SilentSpeechService: SpeechService {
    var isSpeechAudioEnabled: Bool {
        false
    }

    func prepareSpeechAudio(_ text: String) async throws {
    }

    func speak(_ text: String) async throws {
    }
}
