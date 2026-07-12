@preconcurrency import AVFoundation
import Foundation

@MainActor
final class OpenAIDictationService: NSObject, DictationService {
    struct Configuration {
        let apiKey: String
        let transcriptionModel: String
    }

    private let configuration: Configuration
    private let session: URLSession
    private let audioEngine = AVAudioEngine()
    private let targetAudioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var webSocketTask: URLSessionWebSocketTask?
    private var isSessionReady = false
    private var bufferedAudioChunks: [Data] = []
    private var sessionReadyContinuations: [CheckedContinuation<Void, Error>] = []
    private var transcriptContinuation: CheckedContinuation<String, Error>?
    private var latestTranscript = ""
    private var pendingError: Error?
    var onTranscriptChange: ((String) -> Void)?

    init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func startRecording() async throws {
        guard webSocketTask == nil else { return }

        let hasPermission = await requestRecordPermission()
        guard hasPermission else {
            throw OpenAIDictationServiceError.microphonePermissionDenied
        }

        latestTranscript = ""
        pendingError = nil
        isSessionReady = false
        bufferedAudioChunks = []
        try startAudioCapture()

        let webSocketTask = try makeWebSocketTask()
        self.webSocketTask = webSocketTask
        webSocketTask.resume()
        receiveEvents(from: webSocketTask)

        Task { @MainActor in
            do {
                try await self.sendSessionUpdate()
                try await self.waitForSessionReady()
            } catch {
                self.finishWithError(error)
            }
        }
    }

    func finishRecording() async throws -> String {
        if let pendingError {
            self.pendingError = nil
            throw pendingError
        }

        guard webSocketTask != nil else {
            throw OpenAIDictationServiceError.noRecording
        }

        stopAudioCapture()
        if !isSessionReady {
            try await waitForSessionReady()
        }
        try await flushBufferedAudioChunks()
        try await sendEvent(["type": "input_audio_buffer.commit"])

        return try await withCheckedThrowingContinuation { continuation in
            transcriptContinuation = continuation

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard self.transcriptContinuation != nil else { return }
                self.finishWithError(OpenAIDictationServiceError.transcriptionTimedOut)
            }

        }
    }

    func cancelRecording() {
        stopAudioCapture()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isSessionReady = false
        bufferedAudioChunks = []
        resumeSessionReadyContinuations(throwing: OpenAIDictationServiceError.cancelled)
        finishWithError(OpenAIDictationServiceError.cancelled)
    }

    private func makeWebSocketTask() throws -> URLSessionWebSocketTask {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "intent", value: "transcription")]
        guard let url = components.url else {
            throw OpenAIDictationServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        return session.webSocketTask(with: request)
    }

    private func sendSessionUpdate() async throws {
        try await sendEvent([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24_000
                        ],
                        "transcription": [
                            "model": configuration.transcriptionModel,
                            "language": "en",
                            "delay": "low"
                        ]
                    ]
                ]
            ]
        ])
    }

    private func waitForSessionReady() async throws {
        if isSessionReady { return }

        try await withCheckedThrowingContinuation { continuation in
            sessionReadyContinuations.append(continuation)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !self.isSessionReady, !self.sessionReadyContinuations.isEmpty else { return }
                self.finishSessionReady(with: OpenAIDictationServiceError.sessionConfigurationTimedOut)
            }
        }
    }

    private func startAudioCapture() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetAudioFormat) else {
            throw OpenAIDictationServiceError.audioConversionUnavailable
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let pcmData: Data
            do {
                pcmData = try Self.convertToPCM16(buffer, converter: converter, targetAudioFormat: self.targetAudioFormat)
            } catch {
                Task { @MainActor in self.finishWithError(error) }
                return
            }

            guard !pcmData.isEmpty else { return }

            Task { @MainActor in
                do {
                    try await self.appendAudioChunk(pcmData)
                } catch {
                    self.finishWithError(error)
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private nonisolated static func convertToPCM16(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetAudioFormat: AVAudioFormat
    ) throws -> Data {
        let ratio = targetAudioFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetAudioFormat, frameCapacity: outputFrameCapacity) else {
            throw OpenAIDictationServiceError.audioConversionUnavailable
        }

        var didProvideBuffer = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if didProvideBuffer {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideBuffer = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let channelData = outputBuffer.int16ChannelData else {
            throw OpenAIDictationServiceError.audioConversionUnavailable
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }

    private func receiveEvents(from webSocketTask: URLSessionWebSocketTask) {
        Task { @MainActor in
            do {
                while self.webSocketTask === webSocketTask {
                    let message = try await webSocketTask.receive()
                    try self.handle(message)
                }
            } catch {
                guard self.webSocketTask === webSocketTask else { return }
                self.finishWithError(error)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case .data(let messageData):
            data = messageData
        case .string(let messageText):
            data = Data(messageText.utf8)
        @unknown default:
            return
        }

        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else {
            return
        }

        switch type {
        case "session.updated":
            finishSessionReady()
        case "conversation.item.input_audio_transcription.delta":
            if let delta = event["delta"] as? String {
                latestTranscript += delta
                onTranscriptChange?(latestTranscript)
            }
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = event["transcript"] as? String {
                finishWithTranscript(transcript)
            } else {
                finishWithTranscript(latestTranscript)
            }
        case "conversation.item.input_audio_transcription.failed":
            let message = ((event["error"] as? [String: Any])?["message"] as? String)
            finishWithError(OpenAIDictationServiceError.apiError(message: message))
        case "error":
            let message = ((event["error"] as? [String: Any])?["message"] as? String)
            finishWithError(OpenAIDictationServiceError.apiError(message: message))
        default:
            break
        }
    }

    private func sendEvent(_ event: [String: Any?]) async throws {
        guard let webSocketTask else {
            throw OpenAIDictationServiceError.noRecording
        }

        let normalizedEvent = event.compactMapValues { $0 }
        let data = try JSONSerialization.data(withJSONObject: normalizedEvent)
        guard let message = String(data: data, encoding: .utf8) else {
            throw OpenAIDictationServiceError.invalidEvent
        }
        try await webSocketTask.send(.string(message))
    }

    private func appendAudioChunk(_ audioChunk: Data) async throws {
        guard isSessionReady else {
            bufferedAudioChunks.append(audioChunk)
            return
        }

        try await sendAudioChunk(audioChunk)
    }

    private func flushBufferedAudioChunks() async throws {
        let audioChunks = bufferedAudioChunks
        bufferedAudioChunks = []

        for audioChunk in audioChunks {
            try await sendAudioChunk(audioChunk)
        }
    }

    private func sendAudioChunk(_ audioChunk: Data) async throws {
        try await sendEvent([
            "type": "input_audio_buffer.append",
            "audio": audioChunk.base64EncodedString()
        ])
    }

    private func finishSessionReady(with error: Error? = nil) {
        if let error {
            pendingError = error
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isSessionReady = false
            bufferedAudioChunks = []
            resumeSessionReadyContinuations(throwing: error)
        } else {
            isSessionReady = true
            resumeSessionReadyContinuations()
            Task { @MainActor in
                do {
                    try await self.flushBufferedAudioChunks()
                } catch {
                    self.finishWithError(error)
                }
            }
        }
    }

    private func resumeSessionReadyContinuations(throwing error: Error? = nil) {
        let continuations = sessionReadyContinuations
        sessionReadyContinuations = []

        for continuation in continuations {
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    private func finishWithTranscript(_ transcript: String) {
        guard let transcriptContinuation else { return }
        self.transcriptContinuation = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isSessionReady = false
        bufferedAudioChunks = []
        transcriptContinuation.resume(returning: transcript)
    }

    private func finishWithError(_ error: Error) {
        if !sessionReadyContinuations.isEmpty {
            finishSessionReady(with: error)
            return
        }

        guard let transcriptContinuation else {
            pendingError = error
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            isSessionReady = false
            bufferedAudioChunks = []
            return
        }
        self.transcriptContinuation = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isSessionReady = false
        bufferedAudioChunks = []
        transcriptContinuation.resume(throwing: error)
    }

    private func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }
}

private enum OpenAIDictationServiceError: LocalizedError {
    case microphonePermissionDenied
    case noRecording
    case invalidURL
    case invalidEvent
    case audioConversionUnavailable
    case sessionConfigurationTimedOut
    case transcriptionTimedOut
    case cancelled
    case apiError(message: String?)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission is required for dictation."
        case .noRecording:
            "No dictation recording was found."
        case .invalidURL:
            "OpenAI realtime transcription URL is invalid."
        case .invalidEvent:
            "OpenAI realtime transcription event could not be encoded."
        case .audioConversionUnavailable:
            "Microphone audio could not be converted for realtime transcription."
        case .sessionConfigurationTimedOut:
            "OpenAI realtime transcription session setup timed out."
        case .transcriptionTimedOut:
            "OpenAI realtime transcription timed out."
        case .cancelled:
            "Dictation was cancelled."
        case .apiError(let message):
            message ?? "OpenAI realtime transcription failed."
        }
    }
}
