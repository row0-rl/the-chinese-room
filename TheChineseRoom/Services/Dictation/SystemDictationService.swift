import AVFoundation
import Foundation
import Speech

@MainActor
final class SystemDictationService: DictationService {
    var onTranscriptChange: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?
    private var latestTranscript = ""

    func startRecording(localeIdentifier: String) async throws {
        cancelRecording()
        try await requestPermissions()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)),
              recognizer.isAvailable else {
            throw SystemDictationServiceError.localeUnavailable(localeIdentifier)
        }

        #if !targetEnvironment(simulator)
        guard recognizer.supportsOnDeviceRecognition else {
            throw SystemDictationServiceError.localeUnavailable(localeIdentifier)
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        #if targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = false
        #else
        request.requiresOnDeviceRecognition = true
        #endif
        request.addsPunctuation = true
        recognitionRequest = request
        latestTranscript = ""
        pendingResult = nil

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.latestTranscript = result.bestTranscription.formattedString
                    self.onTranscriptChange?(self.latestTranscript)
                    if result.isFinal {
                        self.complete(with: .success(self.latestTranscript))
                    }
                }
                if let error {
                    self.complete(with: .failure(error))
                }
            }
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    func finishRecording() async throws -> String {
        if let pendingResult {
            self.pendingResult = nil
            return try pendingResult.get()
        }
        guard let request = recognitionRequest else {
            throw SystemDictationServiceError.noRecording
        }
        stopAudioCapture()
        request.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            if let pendingResult {
                self.pendingResult = nil
                complete(with: pendingResult)
            }
        }
    }

    func cancelRecording() {
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        if completion != nil {
            complete(with: .failure(CancellationError()))
        }
        pendingResult = nil
        clearRecognitionState()
    }

    private func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw SystemDictationServiceError.speechPermissionDenied
        }

        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        guard microphoneAllowed else {
            throw SystemDictationServiceError.microphonePermissionDenied
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func complete(with result: Result<String, Error>) {
        guard let completion else {
            pendingResult = result
            return
        }
        self.completion = nil
        completion.resume(with: result)
        clearRecognitionState()
    }

    private func clearRecognitionState() {
        recognitionTask = nil
        recognitionRequest = nil
    }
}

private enum SystemDictationServiceError: LocalizedError {
    case noRecording
    case speechPermissionDenied
    case microphonePermissionDenied
    case localeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noRecording:
            "No dictation recording is active."
        case .speechPermissionDenied:
            "Speech recognition permission is required for dictation."
        case .microphonePermissionDenied:
            "Microphone permission is required for dictation."
        case .localeUnavailable(let locale):
            "On-device dictation is unavailable for \(locale)."
        }
    }
}
