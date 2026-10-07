import AVFoundation
import Foundation
import Speech

/// Only observable/UI-facing state lives on the main actor.
@MainActor
final class SystemDictationService: DictationService {
    var onTranscriptChange: ((String) -> Void)?
    private let worker = DictationWorker()
    private var generation = UUID()
    private var cancellation: Task<Void, Never>?

    func prepare(localeIdentifier: String) {
        Task { await worker.prepare(localeIdentifier: localeIdentifier) }
    }

    func startRecording(localeIdentifier: String) async throws {
        let id = UUID()
        generation = id
        await cancellation?.value
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        await worker.setTranscriptHandler(id: id) { [weak self] text in
            Task { @MainActor in
                guard let self, self.generation == id else { return }
                self.onTranscriptChange?(text)
            }
        }
        try Task.checkCancellation()
        guard generation == id else { throw CancellationError() }
        try await worker.startRecording(localeIdentifier: localeIdentifier, id: id)
        guard generation == id else { throw CancellationError() }
        try Task.checkCancellation()
    }

    func finishRecording() async throws -> String {
        try await worker.finishRecording()
    }

    func cancelRecording() {
        generation = UUID()
        let previous = cancellation
        cancellation = Task {
            await previous?.value
            await worker.cancelRecording()
        }
    }

    #if DEBUG
    static func runSmokeTest() async {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVAudioApplication.shared.recordPermission == .granted else {
            print("[Dictation test] SKIP: microphone and speech permissions must already be granted")
            return
        }
        let service = SystemDictationService()
        let locale = LanguageModeStorage.currentMode?.source.localeIdentifier ?? "en-US"
        service.prepare(localeIdentifier: locale)
        for attempt in 1...3 {
            do {
                let start = Date()
                var uiTicks = 0
                let heartbeat = Task { @MainActor in
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .milliseconds(10)) } catch { return }
                        uiTicks += 1
                    }
                }
                defer { heartbeat.cancel() }
                try await service.startRecording(localeIdentifier: locale)
                print("[Dictation test] attempt=\(attempt) ready=\(Date().timeIntervalSince(start))s mainActorTicks=\(uiTicks) engineRunning=\((await service.worker.captureState()).running)")
                try await Task.sleep(for: .milliseconds(250))
                service.cancelRecording()
                await service.cancellation?.value
                print("[Dictation test] canceled engineRunning=\((await service.worker.captureState()).running) tap=\((await service.worker.captureState()).tap)")
            } catch {
                service.cancelRecording()
                print("[Dictation test] FAIL: \(error)")
                return
            }
        }
        print("[Dictation test] COMPLETE: startup/cancellation only; live transcription accuracy not tested")
    }
    #endif

}

/// Explicit dispatch executor: actor isolation alone does not select a dedicated queue.
private final class DictationExecutor: SerialExecutor, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.thechineseroom.dictation", qos: .userInitiated)
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        queue.async { job.runSynchronously(on: self.asUnownedSerialExecutor()) }
    }
}

/// All audio objects and lifecycle mutations are confined to this executor.
private actor DictationWorker {
    nonisolated private let executor = DictationExecutor()
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }
    private var onTranscriptChange: (@Sendable (String) -> Void)?

    func setTranscriptHandler(id: UUID, _ handler: @escaping @Sendable (String) -> Void) {
        requestID = id
        onTranscriptChange = handler
    }

    func captureState() -> (running: Bool, tap: Bool) { (audioEngine.isRunning, hasTap) }
    private let audioEngine = AVAudioEngine()
    private var recognizers: [String: SFSpeechRecognizer] = [:]
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var completion: CheckedContinuation<String, Error>?
    private var pendingResult: Result<String, Error>?
    private var latestTranscript = ""
    private var requestID = UUID()
    private var hasTap = false
    private var ownsAudioSession = false
    private var finishTimeout: Task<Void, Never>?

    func prepare(localeIdentifier: String) {
        // Prepare recognition objects without requesting access or opening the mic.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              recognizers[localeIdentifier] == nil else { return }
        recognizers[localeIdentifier] = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    func startRecording(localeIdentifier: String, id: UUID) async throws {
        guard requestID == id else { throw CancellationError() }
        cancelRecording()
        requestID = id
        let started = Date()
        precondition(!Thread.isMainThread, "Microphone startup must not run on the UI thread")
        do {
            try await requestPermissions(for: id)
            try Task.checkCancellation()
            guard requestID == id else { throw CancellationError() }
            prepare(localeIdentifier: localeIdentifier)
            guard let recognizer = recognizers[localeIdentifier], recognizer.isAvailable else {
                throw SystemDictationServiceError.localeUnavailable(localeIdentifier)
            }
            #if !targetEnvironment(simulator)
            guard recognizer.supportsOnDeviceRecognition else {
                throw SystemDictationServiceError.localeUnavailable(localeIdentifier)
            }
            #endif
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            #if !targetEnvironment(simulator)
            request.requiresOnDeviceRecognition = true
            #endif
            request.addsPunctuation = true
            recognitionRequest = request
            latestTranscript = ""

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            ownsAudioSession = true
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SystemDictationServiceError.noRecording
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            audioEngine.prepare()
            try audioEngine.start()
            // Capture into the request first so recognition setup doesn't lose initial audio.
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                Task { await self?.receive(transcript: transcript, isFinal: isFinal, error: error, id: id) }
            }
            #if DEBUG
            print("[Dictation] microphone ready in \(Date().timeIntervalSince(started))s")
            #endif
        } catch {
            if requestID == id { cancelRecording() }
            throw error
        }
    }

    private func receive(transcript: String?, isFinal: Bool, error: Error?, id: UUID) {
        guard requestID == id, pendingResult == nil else { return }
        if let transcript {
            latestTranscript = transcript
            onTranscriptChange?(transcript)
            if isFinal { complete(with: .success(transcript)); return }
        }
        if let error {
            let speechError = error as NSError
            // Apple's documented no-speech result is an empty recording, not a UI error.
            if speechError.domain == "kAFAssistantErrorDomain", speechError.code == 1110 {
                onTranscriptChange?("")
                complete(with: .success(""))
            } else {
                complete(with: .failure(error))
            }
        }
    }

    func finishRecording() async throws -> String {
        stopAudioCapture()
        if let result = pendingResult {
            clearRecognitionState()
            return try result.get()
        }
        guard let request = recognitionRequest else { throw SystemDictationServiceError.noRecording }
        request.endAudio()
        let id = requestID
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            finishTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await self?.finishTimedOut(id: id)
            }
        }
    }

    private func finishTimedOut(id: UUID) {
        guard requestID == id else { return }
        complete(with: .failure(SystemDictationServiceError.finalizationTimedOut))
    }

    func cancelRecording() {
        requestID = UUID()
        stopAudioCapture()
        let waiting = completion
        completion = nil
        clearRecognitionState()
        waiting?.resume(throwing: CancellationError())
    }

    private func requestPermissions(for id: UUID) async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        try Task.checkCancellation()
        guard requestID == id else { throw CancellationError() }
        guard status == .authorized else { throw SystemDictationServiceError.speechPermissionDenied }
        let micStatus = AVAudioApplication.shared.recordPermission
        let allowed: Bool
        if micStatus == .undetermined {
            allowed = await AVAudioApplication.requestRecordPermission()
        } else {
            allowed = micStatus == .granted
        }
        guard allowed else { throw SystemDictationServiceError.microphonePermissionDenied }
    }

    private func stopAudioCapture() {
        if hasTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        if audioEngine.isRunning { audioEngine.stop() }
        if ownsAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            ownsAudioSession = false
        }
    }

    private func complete(with result: Result<String, Error>) {
        stopAudioCapture()
        finishTimeout?.cancel()
        finishTimeout = nil
        guard let waiting = completion else {
            pendingResult = result
            return
        }
        completion = nil
        clearRecognitionState()
        waiting.resume(with: result)
    }

    private func clearRecognitionState() {
        requestID = UUID()
        finishTimeout?.cancel()
        finishTimeout = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        pendingResult = nil
    }
}

private enum SystemDictationServiceError: LocalizedError {
    case finalizationTimedOut
    case noRecording
    case speechPermissionDenied
    case microphonePermissionDenied
    case localeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .finalizationTimedOut:
            "Dictation took too long to finish. Please try again."
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
