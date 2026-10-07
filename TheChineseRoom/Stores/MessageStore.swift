import Foundation
import SwiftData

@MainActor
@Observable
final class MessageStore {
    let appleTranslation: AppleTranslationService?
    private let service: MessageService
    private let messageQueue: MessageQueueActor
    private let speechService: SpeechService
    private var dictationService: DictationService
    private let persistsMessageHistory: Bool
    let usesLocalMessages: Bool
    private(set) var messages: [LearningMessage]
    private(set) var currentIndex: Int
    private(set) var generationError: String?
    private(set) var isGenerating = false
    private(set) var isSpeaking = false
    private(set) var isStartingDictation = false
    private var dictationRequestID = UUID()
    private(set) var isDictating = false
    private(set) var isTranscribing = false
    private(set) var pendingDictationText: String?
    var pendingDictationID: UUID { dictationRequestID }
    private(set) var isPreparingNextRandom = false
    private(set) var isShowingBlankCard = false
    private(set) var dictatedText = ""
    private(set) var currentLanguageMode: LanguageMode
    private var modelContext: ModelContext?
    private var hasLoadedPersistedSession = false
    private var sessionsByModeID: [String: MessageSession] = [:]
    private var preparedNextRandomMessage: LearningMessage?
    private var preparedNextRandomSourceID: UUID?
    private var autoSpeechTask: Task<Void, Never>?
    private var lastAutoSpokenMessageID: UUID?
    private var speechRequestID = UUID()
    private var hanjaRequests: Set<UUID> = []
    private var hanjaFailures: Set<UUID> = []
    private var pronunciationRequests: Set<UUID> = []
    private var pronunciationFailures: Set<UUID> = []

    func isLoadingPronunciation(for messageID: UUID) -> Bool {
        pronunciationRequests.contains(messageID)
    }

    func pronunciationFailed(for messageID: UUID) -> Bool {
        pronunciationFailures.contains(messageID)
    }

    var currentMessage: LearningMessage {
        messages[currentIndex]
    }

    var previousCardMessage: LearningMessage? {
        guard currentIndex > 0 else { return nil }
        return messages[currentIndex - 1]
    }

    var nextCardMessage: LearningMessage? {
        cardMessage(at: 1)
    }

    /// Includes the prepared message just beyond saved history so the pager can
    /// draw both neighbors of the destination before the swipe completes.
    func cardMessage(at relativePosition: Int) -> LearningMessage? {
        let index = currentIndex + relativePosition
        guard index >= 0 else { return nil }
        if index < messages.count { return messages[index] }
        guard index == messages.count,
              preparedNextRandomSourceID == messages.last?.id else { return nil }
        return preparedNextRandomMessage
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var modelAvailabilityMessage: String? {
        guard !usesLocalMessages else { return nil }
        return AppleMessageRuntime.availabilityMessage(languages: [currentLanguageMode.source, currentLanguageMode.target])
    }

    var nextRandomPreviewText: String? {
        if currentIndex < messages.count - 1 {
            return messages[currentIndex + 1].normalizedSourceText
        }

        guard preparedNextRandomSourceID == currentMessage.id else { return nil }
        return preparedNextRandomMessage?.normalizedSourceText
    }

    func availableVoices(for mode: LanguageMode) -> [SpeechVoice] {
        speechService.availableVoices(localeIdentifier: mode.target.localeIdentifier)
    }

    func selectedVoiceIdentifier(for mode: LanguageMode) -> String? {
        SpeechVoiceStorage.voiceIdentifier(for: mode)
    }

    func updateVoiceIdentifier(_ voiceIdentifier: String?, for mode: LanguageMode) {
        SpeechVoiceStorage.save(voiceIdentifier, for: mode)
    }

    func isLoadingHanja(for messageID: UUID) -> Bool { hanjaRequests.contains(messageID) }
    func hanjaFailed(for messageID: UUID) -> Bool { hanjaFailures.contains(messageID) }

    private func annotationMessage(_ id: UUID) -> LearningMessage? {
        messages.first { $0.id == id } ?? (preparedNextRandomMessage?.id == id ? preparedNextRandomMessage : nil)
    }

    private func updateAnnotations(for id: UUID, _ update: (inout LearningMessage) -> Void) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            update(&messages[index])
            saveCurrentSession()
        } else if preparedNextRandomMessage?.id == id {
            update(&preparedNextRandomMessage!)
        }
    }

    private func prepareAnnotations(for id: UUID) {
        // Automatic preparation runs once; tapping can still retry a failed request.
        if !pronunciationFailures.contains(id) { ensurePronunciation(for: id) }
        if !hanjaFailures.contains(id) { ensureHanja(for: id) }
    }

    func ensureHanja(for messageID: UUID) {
        guard HanjaAnnotation.supports(currentLanguageMode),
              let message = annotationMessage(messageID),
              message.hanjaAnnotations == nil,
              hanjaRequests.insert(messageID).inserted else { return }
        hanjaFailures.remove(messageID)
        let mode = currentLanguageMode
        Task { [weak self] in
            guard let self else { return }
            let result = await service.hanjaAnnotations(for: message, languageMode: mode)
            hanjaRequests.remove(messageID)
            guard currentLanguageMode == mode, annotationMessage(messageID) != nil else { return }
            guard let result else {
                hanjaFailures.insert(messageID)
                return
            }
            // An empty result is a successful "no Hanja" response and is cached too.
            updateAnnotations(for: messageID) { $0.hanjaAnnotations = result }
        }
    }

    func ensurePronunciation(for messageID: UUID) {
        guard let message = annotationMessage(messageID) else { return }
        let system = PronunciationNotationSystem.fixedSystem(for: currentLanguageMode.target)
        switch system {
        case .hepburnRomanization:
            guard message.japanesePronunciation == nil else { return }
        case .ipa:
            guard message.ipaPronunciation == nil else { return }
        default: return
        }
        guard pronunciationRequests.insert(messageID).inserted else { return }
        pronunciationFailures.remove(messageID)

        let text = message.targetText
        let languageMode = currentLanguageMode
        Task { [weak self] in
            guard let self else { return }
            var japanese: [JapanesePronunciationUnit]?
            var ipa: [IPAPronunciationUnit]?
            if system == .ipa {
                ipa = await service.ipaPronunciation(for: text, languageMode: languageMode)
            } else {
                japanese = await service.japanesePronunciation(for: text, languageMode: languageMode)
            }
            pronunciationRequests.remove(messageID)
            guard currentLanguageMode == languageMode, annotationMessage(messageID) != nil else { return }
            guard japanese != nil || ipa != nil else {
                pronunciationFailures.insert(messageID)
                return
            }
            updateAnnotations(for: messageID) { message in
                if let japanese { message.japanesePronunciation = japanese }
                if let ipa { message.ipaPronunciation = ipa }
            }
        }
    }


    func previewVoice(_ voiceIdentifier: String?, for mode: LanguageMode) async throws {
        try await speechService.speak(
            LanguageCatalog.speechPreview(for: mode.target),
            localeIdentifier: mode.target.localeIdentifier,
            voiceIdentifier: voiceIdentifier
        )
    }

    init(configuration: AppConfiguration, initialLanguageMode: LanguageMode = LanguageMode.defaultMode) {
        let translator = AppleTranslationService()
        self.appleTranslation = translator
        let messageService = FoundationModelsMessageService(runtime: AppleMessageRuntime(), translator: translator)
        self.service = messageService
        self.messageQueue = MessageQueueActor(service: messageService)
        self.speechService = OnDeviceSpeechService()
        self.dictationService = SystemDictationService()
        self.persistsMessageHistory = configuration.persistsMessageHistory
        self.usesLocalMessages = false
        self.currentLanguageMode = initialLanguageMode
        self.messages = [MockMessageService.openingMessage(for: initialLanguageMode)]
        self.currentIndex = 0
        bindDictationUpdates()
    }

    init(
        service: MessageService,
        speechService: SpeechService? = nil,
        dictationService: DictationService? = nil,
        usesLocalMessages: Bool = true,
        initialLanguageMode: LanguageMode = LanguageMode.defaultMode
    ) {
        self.appleTranslation = nil
        self.service = service
        self.messageQueue = MessageQueueActor(service: service)
        self.speechService = speechService ?? SilentSpeechService()
        self.dictationService = dictationService ?? UnavailableDictationService()
        self.persistsMessageHistory = false
        self.usesLocalMessages = usesLocalMessages
        self.currentLanguageMode = initialLanguageMode
        self.messages = [MockMessageService.openingMessage(for: initialLanguageMode)]
        self.currentIndex = 0
        bindDictationUpdates()
    }

    func attachPersistence(_ modelContext: ModelContext) {
        // Keep history in memory while persistence is disabled. Existing saved
        // sessions are left intact so the feature can be enabled again later.
        self.modelContext = persistsMessageHistory ? modelContext : nil
        guard !hasLoadedPersistedSession else { return }

        hasLoadedPersistedSession = true
        loadCurrentSession()
        scheduleAutoSpeakCurrentMessage()
        Task {
            await messageQueue.reset(unlessFor: currentMessage.id)
            await prepareNextRandomMessage()
        }
    }

    func nextRandomMessage() async {
        generationError = nil
        guard !isGenerating, !isTranscribing else { return }

        if currentIndex < messages.count - 1 {
            isShowingBlankCard = false
            currentIndex += 1
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
            Task { await prepareNextRandomMessage() }
            return
        }

        let sourceMessage = currentMessage
        let requestedLanguageMode = currentLanguageMode
        isShowingBlankCard = true
        isGenerating = true
        defer { isGenerating = false }

        do {
            let nextMessage = try await messageQueue.consumeNext(
                after: sourceMessage,
                languageMode: requestedLanguageMode,
                recentMessages: recentHistoryMessages()
            )
            guard currentMessage.id == sourceMessage.id, currentLanguageMode == requestedLanguageMode else {
                isShowingBlankCard = false
                return
            }
            messages.append(preparedNextRandomMessage?.id == nextMessage.id ? preparedNextRandomMessage! : nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
            Task { await prepareNextRandomMessage() }
        } catch {
            guard currentMessage.id == sourceMessage.id, currentLanguageMode == requestedLanguageMode else { return }
            isShowingBlankCard = false
            logError(error, context: "Generating next random message")
        }
    }

    func submit(_ input: String) async {
        generationError = nil
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        guard !isGenerating, !isTranscribing else { return }
        await appendNextMessage {
            try await service.message(for: trimmedInput, languageMode: currentLanguageMode)
        }
        if generationError == nil { Task { await prepareNextRandomMessage() } }
    }

    func updateLanguageMode(_ newLanguageMode: LanguageMode) {
        generationError = nil
        guard currentLanguageMode != newLanguageMode else {
            LanguageModeStorage.save(newLanguageMode)
            return
        }

        cancelDictation()
        saveCurrentSession()
        currentLanguageMode = newLanguageMode
        dictationService.prepare(localeIdentifier: newLanguageMode.source.localeIdentifier)
        LanguageModeStorage.save(newLanguageMode)
        loadCurrentSession()
        dictatedText = ""
        isShowingBlankCard = false
        clearPreparedNextRandomMessage()
        scheduleAutoSpeakCurrentMessage()
        Task {
            await messageQueue.reset(unlessFor: currentMessage.id)
            await prepareNextRandomMessage()
        }
    }

    func previousMessage() {
        guard canGoBack else { return }
        isShowingBlankCard = false
        currentIndex -= 1
        saveCurrentSession()
        scheduleAutoSpeakCurrentMessage()
        Task { await prepareNextRandomMessage() }
    }

    func commitNextVisibleMessage() {
        generationError = nil
        isShowingBlankCard = false

        if currentIndex < messages.count - 1 {
            currentIndex += 1
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
            Task { await prepareNextRandomMessage() }
            return
        }

        guard preparedNextRandomSourceID == currentMessage.id, let preparedNextRandomMessage else { return }

        messages.append(preparedNextRandomMessage)
        currentIndex = messages.count - 1
        clearPreparedNextRandomMessage()
        saveCurrentSession()
        scheduleAutoSpeakCurrentMessage()
        Task { await prepareNextRandomMessage() }
    }

    func showBlankNextMessage() {
        generationError = nil
        guard currentIndex == messages.count - 1, !isGenerating else { return }
        isShowingBlankCard = true
    }

    func finishBlankNextMessage() async {
        guard isShowingBlankCard, !isGenerating else { return }

        let sourceMessage = currentMessage
        let requestedLanguageMode = currentLanguageMode
        isGenerating = true
        defer { isGenerating = false }

        do {
            let nextMessage = try await messageQueue.consumeNext(
                after: sourceMessage,
                languageMode: requestedLanguageMode,
                recentMessages: recentHistoryMessages()
            )
            guard currentMessage.id == sourceMessage.id, currentLanguageMode == requestedLanguageMode else {
                isShowingBlankCard = false
                return
            }
            messages.append(preparedNextRandomMessage?.id == nextMessage.id ? preparedNextRandomMessage! : nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
            Task { await prepareNextRandomMessage() }
        } catch {
            guard currentMessage.id == sourceMessage.id, currentLanguageMode == requestedLanguageMode else { return }
            isShowingBlankCard = false
            logError(error, context: "Generating next visible message")
        }
    }

    func commitPreviousVisibleMessage() {
        previousMessage()
    }

    func startDictation() async {
        guard !Task.isCancelled, !isStartingDictation, !isDictating, !isTranscribing, !isGenerating else { return }
        let id = UUID()
        dictationRequestID = id
        generationError = nil
        dictatedText = ""
        isStartingDictation = true
        pendingDictationText = ""
        clearPreparedNextRandomMessage()
        autoSpeechTask?.cancel()
        speechRequestID = UUID()
        speechService.stop()
        isSpeaking = false
        do {
            try await dictationService.startRecording(localeIdentifier: currentLanguageMode.source.localeIdentifier)
            guard dictationRequestID == id else { return }
            try Task.checkCancellation()
            isStartingDictation = false
            isDictating = true
        } catch {
            guard dictationRequestID == id else { return }
            dictationService.cancelRecording()
            isStartingDictation = false
            isDictating = false
            pendingDictationText = nil
            dictatedText = ""
            if !isCancellationError(error) { logError(error, context: "Starting dictation") }
        }
    }

    func finishDictationAndSubmit() async {
        if isStartingDictation { cancelDictation(); return }
        generationError = nil
        guard isDictating else { return }

        isDictating = false
        isTranscribing = true
        let id = dictationRequestID
        defer {
            isTranscribing = false
            if dictationRequestID == id {
                pendingDictationText = nil
                dictatedText = ""
            }
        }

        do {
            let transcript = try await dictationService.finishRecording()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard dictationRequestID == id, !transcript.isEmpty else { return }
            dictatedText = transcript
            pendingDictationText = transcript

            await appendNextMessage(dictationID: id) {
                try await service.message(for: transcript, languageMode: currentLanguageMode)
            }
            dictatedText = ""
            if generationError == nil { Task { await prepareNextRandomMessage() } }
        } catch {
            if dictationRequestID == id && !isCancellationError(error) {
                logError(error, context: "Finishing dictation and submitting message")
            }
        }
    }

    func cancelDictation() {
        guard isStartingDictation || isDictating || isTranscribing else { return }
        dictationRequestID = UUID()
        pendingDictationText = nil
        dictationService.cancelRecording()
        isStartingDictation = false
        isDictating = false
        dictatedText = ""
    }

    func speakCurrentMessage() async {
        await speakCurrentMessage(isAutomatic: false)
    }

    private func speakCurrentMessage(isAutomatic: Bool) async {
        guard !usesLocalMessages, !isStartingDictation, !isDictating, !isTranscribing else { return }

        let requestID = UUID()
        speechRequestID = requestID
        let messageID = currentMessage.id
        isSpeaking = true
        updateCurrentAudioState(.loading)
        defer { if speechRequestID == requestID { isSpeaking = false } }

        do {
            try await speechService.speak(
                currentMessage.targetText,
                localeIdentifier: currentLanguageMode.target.localeIdentifier,
                voiceIdentifier: selectedVoiceIdentifier(for: currentLanguageMode)
            )
            guard speechRequestID == requestID, currentMessage.id == messageID else { return }
            updateCurrentAudioState(.ready)
        } catch is CancellationError {
            return
        } catch {
            if isCancelledURLError(error) {
                return
            }
            guard speechRequestID == requestID, currentMessage.id == messageID else { return }
            updateCurrentAudioState(.failed(error.localizedDescription))
            logError(error, context: isAutomatic ? "Automatically speaking message" : "Speaking message")
        }
    }

    private func appendNextMessage(dictationID: UUID? = nil, _ makeMessage: () async throws -> LearningMessage) async {
        guard !isGenerating else { return }

        isGenerating = true
        defer { isGenerating = false }
        clearPreparedNextRandomMessage()
        await messageQueue.reset()
        let requestedLanguageMode = currentLanguageMode
        guard dictationID == nil || dictationID == dictationRequestID else { return }

        do {
            var nextMessage = try await makeMessage()
            guard currentLanguageMode == requestedLanguageMode,
                  dictationID == nil || dictationID == dictationRequestID else { return }
            if let dictationID {
                // Complete the live card without changing its seeded paper or outline.
                nextMessage = LearningMessage(
                    id: dictationID, sourceText: nextMessage.sourceText,
                    normalizedSourceText: nextMessage.normalizedSourceText,
                    targetText: nextMessage.targetText, literalMeaning: nextMessage.literalMeaning,
                    literalChunks: nextMessage.literalChunks, examples: nextMessage.examples,
                    japanesePronunciation: nextMessage.japanesePronunciation,
                    ipaPronunciation: nextMessage.ipaPronunciation,
                    hanjaAnnotations: nextMessage.hanjaAnnotations, audioState: nextMessage.audioState
                )
            }
            messages.append(preparedNextRandomMessage?.id == nextMessage.id ? preparedNextRandomMessage! : nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
        } catch {
            guard dictationID == nil || dictationID == dictationRequestID else { return }
            isShowingBlankCard = false
            logError(error, context: "Generating submitted message")
        }
    }

    private func prepareNextRandomMessage() async {
        guard currentIndex == messages.count - 1, !isGenerating, pendingDictationText == nil else { return }

        let sourceMessage = currentMessage
        guard preparedNextRandomSourceID != sourceMessage.id, !isPreparingNextRandom else { return }

        isPreparingNextRandom = true
        defer { isPreparingNextRandom = false }

        do {
            let requestedLanguageMode = currentLanguageMode
            let nextMessage = try await messageQueue.prepareNext(
                after: sourceMessage,
                languageMode: requestedLanguageMode,
                recentMessages: recentHistoryMessages()
            )
            guard currentMessage.id == sourceMessage.id else {
                Task { await prepareNextRandomMessage() }
                return
            }
            guard currentLanguageMode == requestedLanguageMode else {
                Task { await prepareNextRandomMessage() }
                return
            }
            guard !isGenerating, !isShowingBlankCard, pendingDictationText == nil else { return }
            preparedNextRandomMessage = nextMessage
            preparedNextRandomSourceID = sourceMessage.id
            prepareAnnotations(for: nextMessage.id)
        } catch {
            guard currentMessage.id == sourceMessage.id else {
                Task { await prepareNextRandomMessage() }
                return
            }
            // A canceled request stays canceled. The next user action can retry.
            if isCancellationError(error) { return }
            logError(error, context: "Prefetching next random message")
        }
    }

    private func clearPreparedNextRandomMessage() {
        preparedNextRandomMessage = nil
        preparedNextRandomSourceID = nil
    }

    private func scheduleAutoSpeakCurrentMessage() {
        prepareAnnotations(for: currentMessage.id)
        guard !usesLocalMessages, !isShowingBlankCard else { return }
        let messageID = currentMessage.id
        guard lastAutoSpokenMessageID != messageID else { return }

        autoSpeechTask?.cancel()
        lastAutoSpokenMessageID = messageID
        autoSpeechTask = Task { [weak self] in
            guard let self else { return }
            await self.speakCurrentMessage(isAutomatic: true)
        }
    }

    private func isCancelledURLError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        return isCancelledURLError(error)
    }

    private func recentHistoryMessages(limit: Int = 20) -> [LearningMessage] {
        guard !messages.isEmpty else { return [] }

        let visibleMessages = messages.prefix(currentIndex + 1)
        return Array(visibleMessages.suffix(limit))
    }

    private func saveCurrentSession() {
        if let modelContext {
            do {
                let modeID = currentLanguageMode.id
                let descriptor = FetchDescriptor<MessageSessionRecord>(
                    predicate: #Predicate { $0.modeID == modeID }
                )
                let record: MessageSessionRecord
                if let existingRecord = try modelContext.fetch(descriptor).first {
                    record = existingRecord
                } else {
                    record = MessageSessionRecord(modeID: modeID, currentIndex: currentIndex, messages: messages)
                    modelContext.insert(record)
                }
                record.update(messages: messages, currentIndex: currentIndex)
                try modelContext.save()
            } catch {
                #if DEBUG
                print("Message session persistence save failed: \(error.localizedDescription)")
                #endif
            }
            return
        }

        sessionsByModeID[currentLanguageMode.id] = MessageSession(
            messages: messages,
            currentIndex: currentIndex
        )
    }

    private func loadCurrentSession() {
        defer {
            for message in messages { prepareAnnotations(for: message.id) }
        }
        if let modelContext {
            do {
                let modeID = currentLanguageMode.id
                let descriptor = FetchDescriptor<MessageSessionRecord>(
                    predicate: #Predicate { $0.modeID == modeID }
                )
                if let record = try modelContext.fetch(descriptor).first {
                    messages = record.messages
                    currentIndex = min(record.currentIndex, max(messages.count - 1, 0))
                } else {
                    messages = [MockMessageService.openingMessage(for: currentLanguageMode)]
                    currentIndex = 0
                    saveCurrentSession()
                }
                clearPreparedNextRandomMessage()
            } catch {
                #if DEBUG
                print("Message session persistence load failed: \(error.localizedDescription)")
                #endif
                messages = [MockMessageService.openingMessage(for: currentLanguageMode)]
                currentIndex = 0
                clearPreparedNextRandomMessage()
            }
            return
        }

        if let session = sessionsByModeID[currentLanguageMode.id] {
            messages = session.messages
            currentIndex = min(session.currentIndex, max(session.messages.count - 1, 0))
            clearPreparedNextRandomMessage()
        } else {
            messages = [MockMessageService.openingMessage(for: currentLanguageMode)]
            currentIndex = 0
            clearPreparedNextRandomMessage()
        }
    }

    private func updateCurrentAudioState(_ audioState: MessageAudioState) {
        messages[currentIndex].audioState = audioState
        saveCurrentSession()
    }

    private func logError(_ error: Error, context: String) {
        generationError = isCancellationError(error)
            ? AppLocale.forLanguage(currentLanguageMode.source).strings.generationInterruptedLabel
            : error.localizedDescription
        let nsError = error as NSError
        let message = """
        [TheChineseRoom] \(context) failed
          error: \(String(reflecting: error))
          domain: \(nsError.domain)
          code: \(nsError.code)
          userInfo: \(nsError.userInfo)
        """
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    private func bindDictationUpdates() {
        dictationService.prepare(localeIdentifier: currentLanguageMode.source.localeIdentifier)
        dictationService.onTranscriptChange = { [weak self] transcript in
            guard let self, self.isStartingDictation || self.isDictating || self.isTranscribing,
                  self.pendingDictationText != nil else { return }
            self.dictatedText = transcript
            self.pendingDictationText = transcript
        }
    }
}

private struct MessageSession {
    var messages: [LearningMessage]
    var currentIndex: Int
}
