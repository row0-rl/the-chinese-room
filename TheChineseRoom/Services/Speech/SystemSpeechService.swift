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

    func availableVoices(localeIdentifier: String) -> [SpeechVoice] {
        let requestedLanguage = Locale.Language(identifier: localeIdentifier)

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let voiceLanguage = Locale.Language(identifier: voice.language)
                return voice.quality == .premium
                    && voiceLanguage.languageCode == requestedLanguage.languageCode
            }
            .map { voice in
                SpeechVoice(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    qualityDescription: voice.quality == .premium ? "Premium" : (voice.quality == .enhanced ? "Enhanced" : "Default")
                )
            }
            .sorted {
                if $0.qualityDescription != $1.qualityDescription {
                    let qualityOrder = ["Premium": 2, "Enhanced": 1, "Default": 0]
                    return qualityOrder[$0.qualityDescription, default: 0] > qualityOrder[$1.qualityDescription, default: 0]
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }


    func prepareSpeechAudio(_ text: String, localeIdentifier: String) async throws {
        guard AVSpeechSynthesisVoice(language: localeIdentifier) != nil else {
            throw SystemSpeechServiceError.voiceUnavailable(localeIdentifier)
        }
    }

    func speak(_ text: String, localeIdentifier: String, voiceIdentifier: String?) async throws {
        synthesizer.stopSpeaking(at: .immediate)
        guard isSpeechAudioEnabled else { return }
        guard let voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(language: localeIdentifier)
        else {
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
