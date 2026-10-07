import Foundation
import SwiftData

// Replace hardware adapters only; exercise the production store and queue.
typealias OnDeviceSpeechService = SilentSpeechService
typealias SystemDictationService = UnavailableDictationService
typealias FoundationModelsMessageService = MockMessageService
extension MockMessageService { init(runtime: AppleMessageRuntime, translator: any TextTranslationService) { self.init() } }
struct AppleMessageRuntime {
    static func availabilityMessage(languages: [LanguageProfile]) -> String? { nil }
}

actor ControlledMessages: MessageService {
    private var pendingHanja: CheckedContinuation<[HanjaAnnotation]?, Never>?
    private(set) var hanjaRequests = 0
    func hanjaAnnotations(for message: LearningMessage, languageMode: LanguageMode) async -> [HanjaAnnotation]? {
        hanjaRequests += 1
        return await withCheckedContinuation { pendingHanja = $0 }
    }
    func completeHanja(_ result: [HanjaAnnotation]?) {
        pendingHanja?.resume(returning: result)
        pendingHanja = nil
    }
    private var pendingIPA: [CheckedContinuation<[IPAPronunciationUnit]?, Never>] = []
    private(set) var ipaRequests = 0
    func ipaPronunciation(for text: String, languageMode: LanguageMode) async -> [IPAPronunciationUnit]? {
        ipaRequests += 1
        return await withCheckedContinuation { pendingIPA.append($0) }
    }
    func completeIPA(_ result: [IPAPronunciationUnit]?) {
        if !pendingIPA.isEmpty { pendingIPA.removeFirst().resume(returning: result) }
    }
    private var pending: [Int: CheckedContinuation<LearningMessage, Error>] = [:]
    private(set) var count = 0
    private(set) var cancellations = 0
    func randomMessage(after: LearningMessage?, languageMode: LanguageMode, recentMessages: [LearningMessage]) async throws -> LearningMessage {
        try await generate()
    }
    func message(for: String, languageMode: LanguageMode) async throws -> LearningMessage { try await generate() }
    private func generate() async throws -> LearningMessage {
        count += 1
        let id = count
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[id] = $0 }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        cancellations += 1
        continuation.resume(throwing: CancellationError())
    }
    func complete(_ id: Int, failing: Bool = false) {
        guard let continuation = pending.removeValue(forKey: id) else { preconditionFailure("Missing request") }
        if failing { continuation.resume(throwing: CancellationError()) }
        else { continuation.resume(returning: MockMessageService.openingMessage(for: .defaultMode)) }
    }
}

@MainActor final class ControlledDictation: DictationService {
    var onTranscriptChange: ((String) -> Void)?
    var starts: [CheckedContinuation<Void, Error>] = []
    var cancellations = 0
    var finishes = 0
    var delaysFinish = false
    var pendingFinish: CheckedContinuation<String, Error>?
    func startRecording(localeIdentifier: String) async throws {
        try await withCheckedThrowingContinuation { starts.append($0) }
    }
    func finishRecording() async throws -> String {
        finishes += 1
        if delaysFinish { return try await withCheckedThrowingContinuation { pendingFinish = $0 } }
        return ""
    }
    func cancelRecording() { cancellations += 1 }
    func ready() { starts.removeFirst().resume() }
}

@main struct MessageLifecycleRegression {
    @MainActor static func waitUntil(_ predicate: () async -> Bool) async {
        for _ in 0..<10000 {
            if await predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Lifecycle transition did not complete")
    }
    @MainActor static func main() async throws {
        // Release during suspended startup cancels, never finishes a nonexistent recording.
        let dictation = ControlledDictation()
        let dictationStore = MessageStore(service: ControlledMessages(), dictationService: dictation)
        let oldStart = Task { await dictationStore.startDictation() }
        await waitUntil { dictation.starts.count == 1 }
        precondition(dictationStore.isStartingDictation && !dictationStore.isDictating)
        precondition(dictationStore.pendingDictationText == "", "Holding must create a card before recording becomes ready")
        let startingCardID = dictationStore.pendingDictationID
        await dictationStore.startDictation()
        precondition(dictation.starts.count == 1, "Repeated gesture updates must not restart capture")
        precondition(dictationStore.pendingDictationID == startingCardID)
        await dictationStore.finishDictationAndSubmit()
        precondition(!dictationStore.isStartingDictation && !dictationStore.isDictating)
        precondition(dictation.finishes == 0 && dictation.cancellations == 1)
        precondition(dictationStore.pendingDictationText == nil, "Release during startup must dismiss the draft")
        dictation.onTranscriptChange?("Late canceled transcript")
        precondition(dictationStore.pendingDictationText == nil && dictationStore.dictatedText.isEmpty)
        // A stale completion must not mark the newer session ready or cancel it.
        let newStart = Task { await dictationStore.startDictation() }
        await waitUntil { dictation.starts.count == 2 }
        dictation.ready()
        await oldStart.value
        precondition(dictationStore.isStartingDictation && !dictationStore.isDictating)
        dictation.ready()
        await newStart.value
        precondition(dictationStore.isDictating && !dictationStore.isStartingDictation)
        await dictationStore.finishDictationAndSubmit()
        precondition(dictation.finishes == 1 && !dictationStore.isDictating && !dictationStore.isTranscribing)
        // Cancellation before the start Task is scheduled must not open the microphone.
        let canceledStart = Task { await dictationStore.startDictation() }
        canceledStart.cancel()
        await canceledStart.value
        precondition(dictation.starts.isEmpty)
        print("PASS: dictation readiness, release during startup, duplicate starts, stale completion, and pre-start cancellation")

        let releaseSpeech = ControlledDictation()
        releaseSpeech.delaysFinish = true
        let releaseMessages = ControlledMessages()
        let releaseStore = MessageStore(service: releaseMessages, dictationService: releaseSpeech)
        let originalID = releaseStore.currentMessage.id
        let releaseStart = Task { await releaseStore.startDictation() }
        await waitUntil { releaseSpeech.starts.count == 1 }
        precondition(releaseStore.pendingDictationText == "")
        let liveCardID = releaseStore.pendingDictationID
        precondition(liveCardID != originalID)
        releaseSpeech.ready()
        await releaseStart.value
        releaseSpeech.onTranscriptChange?("Hello")
        precondition(releaseStore.pendingDictationText == "Hello" && releaseStore.isDictating,
                     "Live words must appear in the card while the button is still held")
        releaseSpeech.onTranscriptChange?("Hello there")
        precondition(releaseStore.pendingDictationText == "Hello there" && releaseStore.pendingDictationID == liveCardID)
        let releaseFinish = Task { await releaseStore.finishDictationAndSubmit() }
        await waitUntil { releaseSpeech.pendingFinish != nil }
        precondition(releaseStore.pendingDictationText == "Hello there")
        releaseSpeech.pendingFinish?.resume(returning: "Hello world")
        releaseSpeech.pendingFinish = nil
        await waitUntil { await releaseMessages.count == 1 }
        precondition(releaseStore.pendingDictationText == "Hello world" && releaseStore.isGenerating)
        precondition(releaseStore.pendingDictationID == liveCardID)
        await releaseMessages.complete(1)
        await releaseFinish.value
        precondition(releaseStore.pendingDictationText == nil && releaseStore.currentMessage.id != originalID)
        precondition(releaseStore.currentMessage.id == liveCardID, "Generation must complete the same live card")
        releaseSpeech.onTranscriptChange?("Late finished transcript")
        precondition(releaseStore.pendingDictationText == nil && releaseStore.dictatedText.isEmpty)
        precondition(dictationStore.pendingDictationText == nil, "Empty dictation must dismiss its pending card")
        print("PASS: live card starts on hold, updates partial transcripts, and keeps its identity through generation")

        let failedSpeech = ControlledDictation()
        let failedStore = MessageStore(service: ControlledMessages(), dictationService: failedSpeech)
        let failedStart = Task { await failedStore.startDictation() }
        await waitUntil { failedSpeech.starts.count == 1 }
        failedSpeech.starts.removeFirst().resume(throwing: DictationServiceError.notConfigured)
        await failedStart.value
        precondition(failedStore.pendingDictationText == nil && !failedStore.isStartingDictation)
        precondition(failedStore.generationError != nil)

        let canceledSpeech = ControlledDictation()
        canceledSpeech.delaysFinish = true
        let canceledMessages = ControlledMessages()
        let canceledStore = MessageStore(service: canceledMessages, dictationService: canceledSpeech)
        let canceledOriginalID = canceledStore.currentMessage.id
        let canceledReady = Task { await canceledStore.startDictation() }
        await waitUntil { canceledSpeech.starts.count == 1 }
        canceledSpeech.ready()
        await canceledReady.value
        canceledSpeech.onTranscriptChange?("Canceled card")
        let canceledFinish = Task { await canceledStore.finishDictationAndSubmit() }
        await waitUntil { canceledSpeech.pendingFinish != nil }
        canceledSpeech.pendingFinish?.resume(returning: "Canceled card")
        canceledSpeech.pendingFinish = nil
        await waitUntil { await canceledMessages.count == 1 }
        canceledStore.cancelDictation()
        precondition(canceledStore.pendingDictationText == nil)
        await canceledMessages.complete(1)
        await canceledFinish.value
        precondition(canceledStore.currentMessage.id == canceledOriginalID && canceledStore.messages.count == 1,
                     "A canceled live card must not return when generation finishes")
        print("PASS: failed startup removes the draft and canceled generation cannot commit a late card")

        // A late reset must preserve an already-running request for this card.
        let service = ControlledMessages()
        let queue = MessageQueueActor(service: service)
        let source = MockMessageService.openingMessage(for: .defaultMode)
        let first = Task { try await queue.consumeNext(after: source, languageMode: .defaultMode, recentMessages: [source]) }
        await waitUntil { await service.count == 1 }
        await queue.reset(unlessFor: source.id)
        let cancelled = await service.cancellations
        precondition(cancelled == 0)
        await service.complete(1)
        _ = try await first.value

        // Submitting while visible generation owns the queue must not cancel it.
        let messages = ControlledMessages()
        let store = MessageStore(service: messages)
        store.showBlankNextMessage()
        let visible = Task { await store.finishBlankNextMessage() }
        await waitUntil { await messages.count == 1 }
        await store.submit("hello")
        let busyCancellations = await messages.cancellations
        precondition(busyCancellations == 0)
        await messages.complete(1, failing: true)
        await visible.value
        precondition(!store.isShowingBlankCard && !store.isGenerating)
        precondition(store.generationError != nil)
        // No automatic retry after a failed visible request.
        for _ in 0..<100 { await Task.yield() }
        let count = await messages.count
        precondition(count == 1)
        // A user swipe can retry successfully.
        store.showBlankNextMessage()
        let retry = Task { await store.finishBlankNextMessage() }
        await waitUntil { await messages.count == 2 }
        await messages.complete(2)
        await retry.value
        precondition(!store.isShowingBlankCard && !store.isGenerating)
        precondition(store.messages.count == 2)

        // Startup prefetch cancellation must not recursively restart itself.
        let background = ControlledMessages()
        let fresh = MessageStore(service: background)
        let container = try ModelContainer(for: MessageSessionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        fresh.attachPersistence(container.mainContext)
        await waitUntil { await background.count == 1 }
        await background.complete(1, failing: true)
        await waitUntil { !fresh.isPreparingNextRandom }
        for _ in 0..<100 { await Task.yield() }
        let backgroundCount = await background.count
        precondition(backgroundCount == 1)
        // IPA is requested once, applied asynchronously, and reused on reopening.
        let ipaService = ControlledMessages()
        let ipaStore = MessageStore(service: ipaService)
        let messageID = ipaStore.currentMessage.id
        ipaStore.ensurePronunciation(for: messageID)
        ipaStore.ensurePronunciation(for: messageID)
        precondition(ipaStore.isLoadingPronunciation(for: messageID))
        await waitUntil { await ipaService.ipaRequests == 1 }
        await ipaService.completeIPA(nil)
        await waitUntil { ipaStore.pronunciationFailed(for: messageID) }
        precondition(!ipaStore.isLoadingPronunciation(for: messageID))
        precondition(ipaStore.currentMessage.ipaPronunciation == nil)
        ipaStore.ensurePronunciation(for: messageID)
        precondition(!ipaStore.pronunciationFailed(for: messageID))
        await waitUntil { await ipaService.ipaRequests == 2 }
        let ipa = [IPAPronunciationUnit(surface: ipaStore.currentMessage.targetText, ipa: "tɛst")]
        await ipaService.completeIPA(ipa)
        await waitUntil { ipaStore.currentMessage.ipaPronunciation == ipa }
        ipaStore.ensurePronunciation(for: messageID)
        for _ in 0..<100 { await Task.yield() }
        let ipaCount = await ipaService.ipaRequests
        precondition(ipaCount == 2)

        let record = MessageSessionRecord(modeID: LanguageMode.defaultMode.id, currentIndex: 0, messages: ipaStore.messages)
        precondition(record.messages.first?.ipaPronunciation == ipa)
        // Records written before IPA existed still decode, with no cached IPA.
        var legacy = try JSONSerialization.jsonObject(with: record.messagesData) as! [[String: Any]]
        legacy[0].removeValue(forKey: "ipaPronunciation")
        record.messagesData = try JSONSerialization.data(withJSONObject: legacy)
        precondition(record.messages.first?.id == messageID)
        precondition(record.messages.first?.ipaPronunciation == nil)
        let hanjaService = ControlledMessages()
        let koreanMode = LanguageMode(source: LanguageCatalog.simplifiedChinese, target: LanguageCatalog.koreanHangul)
        let hanjaStore = MessageStore(service: hanjaService, initialLanguageMode: koreanMode)
        let hanjaID = hanjaStore.currentMessage.id
        hanjaStore.ensureHanja(for: hanjaID)
        hanjaStore.ensureHanja(for: hanjaID)
        await waitUntil { await hanjaService.hanjaRequests == 1 }
        await hanjaService.completeHanja(nil)
        await waitUntil { hanjaStore.hanjaFailed(for: hanjaID) }
        hanjaStore.ensureHanja(for: hanjaID)
        await waitUntil { await hanjaService.hanjaRequests == 2 }
        await hanjaService.completeHanja([])
        await waitUntil { hanjaStore.currentMessage.hanjaAnnotations == [] }
        hanjaStore.ensureHanja(for: hanjaID)
        for _ in 0..<100 { await Task.yield() }
        let hanjaCount = await hanjaService.hanjaRequests
        precondition(hanjaCount == 2, "Empty success must be cached")
        precondition(!hanjaStore.hanjaFailed(for: hanjaID))
        let hanjaRecord = MessageSessionRecord(modeID: koreanMode.id, currentIndex: 0, messages: hanjaStore.messages)
        precondition(hanjaRecord.messages.first?.hanjaAnnotations == [])
        var old = try JSONSerialization.jsonObject(with: hanjaRecord.messagesData) as! [[String: Any]]
        old[0].removeValue(forKey: "hanjaAnnotations")
        hanjaRecord.messagesData = try JSONSerialization.data(withJSONObject: old)
        precondition(hanjaRecord.messages.first?.id == hanjaID)
        precondition(hanjaRecord.messages.first?.hanjaAnnotations == nil)

        precondition(HanjaAnnotation.validated(transformation: "學校에 가요.", text: "학교에 가요.") == [HanjaAnnotation(offset: 0, surface: "학교", hanja: "學校")])
        precondition(HanjaAnnotation.validated(transformation: "學校과 學校.", text: "학교와 학교.") == nil)
        precondition(HanjaAnnotation.validated(transformation: "學校 에 가요.", text: "학교에 가요.") == nil)
        precondition(HanjaAnnotation.validated(transformation: "물이 차가워요.", text: "물이 차가워요.") == [])
        let spans: [(String, String)] = [("😀 ", ""), ("학교", "學校"), ("와 ", ""), ("학교", "學校"), ("에 가요.", "")]
        let annotations = HanjaAnnotation.validated(spans: spans, text: "😀 학교와 학교에 가요.")!
        precondition(annotations.map(\.offset) == [3, 7])
        precondition(HanjaAnnotation.validated(spans: [("학교", "学校"), ("에", "")], text: "학교에") != nil)
        precondition(HanjaAnnotation.validated(spans: [("학교", "學校")], text: "학교에") == nil)
        precondition(HanjaAnnotation.validated(spans: [("학교에", "學校")], text: "학교에") == nil)
        precondition(HanjaAnnotation.validated(spans: [("학교", "school")], text: "학교") == nil)
        precondition(HanjaAnnotation.validated(spans: [("물", "")], text: "물") == [])
        var saved = hanjaStore.currentMessage
        saved.hanjaAnnotations = annotations
        hanjaRecord.update(messages: [saved], currentIndex: 0)
        precondition(hanjaRecord.messages.first?.hanjaAnnotations == annotations)

        // Unsupported modes do not call AI; late results cannot land in another mode.
        ipaStore.ensureHanja(for: messageID)
        let unsupportedRequests = await ipaService.hanjaRequests
        precondition(unsupportedRequests == 0)
        let staleStore = MessageStore(service: hanjaService, initialLanguageMode: koreanMode)
        staleStore.ensureHanja(for: staleStore.currentMessage.id)
        await waitUntil { await hanjaService.hanjaRequests == 3 }
        staleStore.updateLanguageMode(.defaultMode)
        await hanjaService.completeHanja(annotations)
        for _ in 0..<100 { await Task.yield() }
        precondition(staleStore.currentMessage.hanjaAnnotations == nil)
        // Startup and prefetch request annotations without any tap.
        let eagerService = ControlledMessages()
        let eagerStore = MessageStore(service: eagerService)
        eagerStore.attachPersistence(container.mainContext)
        await waitUntil { await eagerService.ipaRequests == 1 }
        await waitUntil { await eagerService.count == 1 }
        await eagerService.completeIPA([])
        await waitUntil { eagerStore.currentMessage.ipaPronunciation == [] }
        await eagerService.complete(1)
        await waitUntil { eagerStore.nextCardMessage != nil }
        await waitUntil { await eagerService.ipaRequests == 2 }
        let preparedID = eagerStore.nextCardMessage!.id
        let preparedIPA = [IPAPronunciationUnit(surface: eagerStore.nextCardMessage!.targetText, ipa: "tɛst")]
        await eagerService.completeIPA(preparedIPA)
        await waitUntil { eagerStore.nextCardMessage?.ipaPronunciation == preparedIPA }
        await eagerStore.nextRandomMessage()
        precondition(eagerStore.currentMessage.id == preparedID)
        precondition(eagerStore.currentMessage.ipaPronunciation == preparedIPA,
                     "Consuming the queue must preserve annotations already prepared in the store")
        let eagerCount = await eagerService.ipaRequests
        precondition(eagerCount == 2)

        let eagerHanjaService = ControlledMessages()
        let eagerHanjaStore = MessageStore(service: eagerHanjaService, initialLanguageMode: koreanMode)
        eagerHanjaStore.attachPersistence(container.mainContext)
        await waitUntil { await eagerHanjaService.hanjaRequests == 1 }
        await eagerHanjaService.completeHanja([])
        await waitUntil { eagerHanjaStore.currentMessage.hanjaAnnotations == [] }
        print("PASS: automatic startup and prefetch annotations, cached results preserved on queue consumption")
        print("PASS: Hanja alignment, particles, repeated words, UTF-16 offsets, request deduplication, retry, empty caching, persistence, and mode isolation")
        print("PASS: IPA request deduplication, failure/retry, async application, caching, persistence, and legacy decoding")
        print("PASS: late reset, busy submission, cancellation recovery, swipe retry, and canceled prefetch")
    }
}
