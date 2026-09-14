import Foundation
import SwiftData

// Replace hardware adapters only; exercise the production store and queue.
typealias SystemSpeechService = SilentSpeechService
typealias SystemDictationService = UnavailableDictationService
typealias FoundationModelsMessageService = MockMessageService
extension MockMessageService { init(runtime: AppleMessageRuntime, translator: any TextTranslationService) { self.init() } }
struct AppleMessageRuntime {
    static func availabilityMessage(languages: [LanguageProfile]) -> String? { nil }
}

actor ControlledMessages: MessageService {
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

@main struct MessageLifecycleRegression {
    @MainActor static func waitUntil(_ predicate: () async -> Bool) async {
        for _ in 0..<10000 {
            if await predicate() { return }
            await Task.yield()
        }
        preconditionFailure("Lifecycle transition did not complete")
    }
    @MainActor static func main() async throws {
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
        print("PASS: late reset, busy submission, cancellation recovery, swipe retry, and canceled prefetch")
    }
}
