import AVFoundation
import Foundation

@MainActor
final class SystemSpeechService: NSObject, SpeechService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeechAudioEnabled: Bool {
        AVAudioSession.sharedInstance().outputVolume > 0
    }

    func prepareSpeechAudio(_ text: String, localeIdentifier: String) async throws {
        guard AVSpeechSynthesisVoice(language: localeIdentifier) != nil else {
            throw SystemSpeechServiceError.voiceUnavailable(localeIdentifier)
        }
    }

    func speak(_ text: String, localeIdentifier: String) async throws {
        synthesizer.stopSpeaking(at: .immediate)
        guard isSpeechAudioEnabled else { return }
        guard let voice = AVSpeechSynthesisVoice(language: localeIdentifier) else {
            throw SystemSpeechServiceError.voiceUnavailable(localeIdentifier)
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
}

private enum SystemSpeechServiceError: LocalizedError {
    case voiceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .voiceUnavailable(let locale):
            "No system speech voice is installed for \(locale)."
        }
    }
}
