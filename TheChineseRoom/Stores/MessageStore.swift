import Foundation
import FoundationModels
import SwiftData

@MainActor
@Observable
final class MessageStore {
    private let service: MessageService
    private let messageQueue: MessageQueueActor
    private let speechService: SpeechService
    private var dictationService: DictationService
    private let languageModel: SystemLanguageModel?
    let usesLocalMessages: Bool
    private(set) var messages: [LearningMessage]
    private(set) var currentIndex: Int
    private(set) var isGenerating = false
    private(set) var isSpeaking = false
    private(set) var isDictating = false
    private(set) var isTranscribing = false
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

    var currentMessage: LearningMessage {
        messages[currentIndex]
    }

    var previousCardMessage: LearningMessage? {
        guard currentIndex > 0 else { return nil }
        return messages[currentIndex - 1]
    }

    var nextCardMessage: LearningMessage? {
        if currentIndex < messages.count - 1 {
            return messages[currentIndex + 1]
        }

        guard preparedNextRandomSourceID == currentMessage.id else { return nil }
        return preparedNextRandomMessage
    }

    var canGoBack: Bool {
        currentIndex > 0
    }

    var modelAvailabilityMessage: String? {
        guard let languageModel else { return nil }
        guard case .unavailable = languageModel.availability else { return nil }
        return FoundationModelsServiceError.unavailable(languageModel.availability).localizedDescription
    }

    var nextRandomPreviewText: String? {
        if currentIndex < messages.count - 1 {
            return messages[currentIndex + 1].normalizedSourceText
        }

        guard preparedNextRandomSourceID == currentMessage.id else { return nil }
        return preparedNextRandomMessage?.normalizedSourceText
    }

    init(configuration: AppConfiguration, initialLanguageMode: LanguageMode = LanguageMode.defaultMode) {
        let messageService = FoundationModelsMessageService(model: configuration.languageModel)
        self.service = messageService
        self.messageQueue = MessageQueueActor(service: messageService)
        self.speechService = SystemSpeechService()
        self.dictationService = SystemDictationService()
        self.languageModel = configuration.languageModel
        self.usesLocalMessages = false
        self.currentLanguageMode = initialLanguageMode
        self.messages = [MockMessageService.openingMessage]
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
        self.service = service
        self.messageQueue = MessageQueueActor(service: service)
        self.speechService = speechService ?? SilentSpeechService()
        self.dictationService = dictationService ?? UnavailableDictationService()
        self.languageModel = nil
        self.usesLocalMessages = usesLocalMessages
        self.currentLanguageMode = initialLanguageMode
        self.messages = [MockMessageService.openingMessage]
        self.currentIndex = 0
        bindDictationUpdates()
    }

    func attachPersistence(_ modelContext: ModelContext) {
        self.modelContext = modelContext
        guard !hasLoadedPersistedSession else { return }

        hasLoadedPersistedSession = true
        loadCurrentSession()
        scheduleAutoSpeakCurrentMessage()
        Task {
            await messageQueue.reset()
            await prepareNextRandomMessage()
        }
    }

    func nextRandomMessage() async {
        guard !isGenerating else { return }

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
            messages.append(nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
        } catch {
            isShowingBlankCard = false
            logError(error, context: "Generating next random message")
        }
        Task { await prepareNextRandomMessage() }
    }

    func submit(_ input: String) async {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        clearPreparedNextRandomMessage()
        await messageQueue.reset()
        await appendNextMessage {
            try await service.message(for: trimmedInput, languageMode: currentLanguageMode)
        }
        Task { await prepareNextRandomMessage() }
    }

    func updateLanguageMode(_ newLanguageMode: LanguageMode) {
        guard currentLanguageMode != newLanguageMode else {
            LanguageModeStorage.save(newLanguageMode)
            return
        }

        saveCurrentSession()
        currentLanguageMode = newLanguageMode
        LanguageModeStorage.save(newLanguageMode)
        loadCurrentSession()
        dictatedText = ""
        isShowingBlankCard = false
        clearPreparedNextRandomMessage()
        scheduleAutoSpeakCurrentMessage()
        Task {
            await messageQueue.reset()
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
            messages.append(nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
        } catch {
            isShowingBlankCard = false
            logError(error, context: "Generating next visible message")
        }
        Task { await prepareNextRandomMessage() }
    }

    func commitPreviousVisibleMessage() {
        previousMessage()
    }

    func startDictation() async {
        guard !isDictating, !isTranscribing, !isGenerating else { return }

        do {
            dictatedText = ""
            isDictating = true
            try await dictationService.startRecording(
                localeIdentifier: currentLanguageMode.source.localeIdentifier
            )
        } catch {
            isDictating = false
            logError(error, context: "Starting dictation")
        }
    }

    func finishDictationAndSubmit() async {
        guard isDictating else { return }

        isDictating = false
        isTranscribing = true
        defer { isTranscribing = false }

        do {
            let transcript = try await dictationService.finishRecording()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { return }
            dictatedText = transcript

            clearPreparedNextRandomMessage()
            await messageQueue.reset()
            await appendNextMessage {
                try await service.message(for: transcript, languageMode: currentLanguageMode)
            }
            dictatedText = ""
            Task { await prepareNextRandomMessage() }
        } catch {
            logError(error, context: "Finishing dictation and submitting message")
        }
    }

    func cancelDictation() {
        guard isDictating else { return }
        dictationService.cancelRecording()
        isDictating = false
        dictatedText = ""
    }

    func speakCurrentMessage() async {
        await speakCurrentMessage(isAutomatic: false)
    }

    private func speakCurrentMessage(isAutomatic: Bool) async {
        guard !usesLocalMessages else { return }

        isSpeaking = true
        updateCurrentAudioState(.loading)
        defer { isSpeaking = false }

        do {
            try await speechService.speak(
                currentMessage.targetText,
                localeIdentifier: currentLanguageMode.target.localeIdentifier
            )
            updateCurrentAudioState(.ready)
        } catch is CancellationError {
            return
        } catch {
            if isCancelledURLError(error) {
                return
            }
            updateCurrentAudioState(.failed(error.localizedDescription))
            logError(error, context: isAutomatic ? "Automatically speaking message" : "Speaking message")
        }
    }

    private func appendNextMessage(_ makeMessage: () async throws -> LearningMessage) async {
        guard !isGenerating else { return }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let nextMessage = try await makeMessage()
            messages.append(nextMessage)
            currentIndex = messages.count - 1
            isShowingBlankCard = false
            clearPreparedNextRandomMessage()
            saveCurrentSession()
            scheduleAutoSpeakCurrentMessage()
        } catch {
            isShowingBlankCard = false
            logError(error, context: "Generating submitted message")
        }
    }

    private func prepareNextRandomMessage() async {
        guard currentIndex == messages.count - 1 else { return }

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
            guard !isGenerating, !isShowingBlankCard else { return }
            preparedNextRandomMessage = nextMessage
            preparedNextRandomSourceID = sourceMessage.id
        } catch {
            guard currentMessage.id == sourceMessage.id else {
                Task { await prepareNextRandomMessage() }
                return
            }
            if isCancellationError(error) {
                Task { await prepareNextRandomMessage() }
                return
            }
            logError(error, context: "Prefetching next random message")
        }
    }

    private func clearPreparedNextRandomMessage() {
        preparedNextRandomMessage = nil
        preparedNextRandomSourceID = nil
    }

    private func scheduleAutoSpeakCurrentMessage() {
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
                    messages = [MockMessageService.openingMessage]
                    currentIndex = 0
                    saveCurrentSession()
                }
                clearPreparedNextRandomMessage()
            } catch {
                #if DEBUG
                print("Message session persistence load failed: \(error.localizedDescription)")
                #endif
                messages = [MockMessageService.openingMessage]
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
            messages = [MockMessageService.openingMessage]
            currentIndex = 0
            clearPreparedNextRandomMessage()
        }
    }

    private func updateCurrentAudioState(_ audioState: MessageAudioState) {
        messages[currentIndex].audioState = audioState
        saveCurrentSession()
    }

    private func logError(_ error: Error, context: String) {
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
        dictationService.onTranscriptChange = { [weak self] transcript in
            self?.dictatedText = transcript
        }
    }
}

private struct MessageSession {
    var messages: [LearningMessage]
    var currentIndex: Int
}
