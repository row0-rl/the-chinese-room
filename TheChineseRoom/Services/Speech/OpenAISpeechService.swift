import AVFoundation
import Foundation

@MainActor
final class OpenAISpeechService: NSObject, SpeechService, AVAudioPlayerDelegate {
    struct Configuration {
        let apiKey: String
        let model: String
        let voice: String
    }

    private let configuration: Configuration
    private let session: URLSession
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/speech")!
    private var audioPlayer: AVAudioPlayer?
    private var audioCache: [String: Data] = [:]

    var isSpeechAudioEnabled: Bool {
        let audioSession = AVAudioSession.sharedInstance()
        // Treat system output volume as the app's TTS gate. At volume 0,
        // skip both OpenAI speech generation and local playback.
        return audioSession.outputVolume > 0
    }

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func prepareSpeechAudio(_ text: String) async throws {
        try configureAudioSessionForSpeech()
        guard isSpeechAudioEnabled else {
            return
        }
        _ = try await cachedSpeechAudio(for: text)
    }

    func speak(_ text: String) async throws {
        audioPlayer?.stop()
        try configureAudioSessionForSpeech()
        guard isSpeechAudioEnabled else {
            return
        }

        let audioData = try await cachedSpeechAudio(for: text)
        let player = try AVAudioPlayer(data: audioData)
        player.delegate = self
        player.prepareToPlay()
        audioPlayer = player
        player.play()
    }

    private func configureAudioSessionForSpeech() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
        try audioSession.setActive(true)
    }

    private func cachedSpeechAudio(for text: String) async throws -> Data {
        if let cachedAudioData = audioCache[text] {
            return cachedAudioData
        }

        let audioData = try await fetchSpeechAudio(for: text)
        audioCache[text] = audioData
        return audioData
    }

    private func fetchSpeechAudio(for text: String) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAISpeechRequest(
                model: configuration.model,
                input: text,
                voice: configuration.voice,
                responseFormat: "mp3"
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAISpeechServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenAISpeechServiceError.apiError(statusCode: httpResponse.statusCode, message: apiErrorMessage(from: data))
        }

        return data
    }

    private func apiErrorMessage(from data: Data) -> String? {
        try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data).error.message
    }
}

private enum OpenAISpeechServiceError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "OpenAI returned invalid speech audio."
        case .apiError(let statusCode, let message):
            message ?? "OpenAI speech request failed with status \(statusCode)."
        }
    }
}

private struct OpenAISpeechRequest: Encodable {
    let model: String
    let input: String
    let voice: String
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case responseFormat = "response_format"
    }
}
