import Foundation

actor MessageQueueActor {
    private let service: MessageService
    private var queuedNext: LearningMessage?
    private var queuedSourceID: UUID?
    private var queuedModeID: String?
    private var queuedHistorySignature: String?
    private var inFlightNext: Task<LearningMessage, Error>?
    private var inFlightSourceID: UUID?
    private var inFlightModeID: String?
    private var inFlightHistorySignature: String?
    private var inFlightID: UUID?

    init(service: MessageService) {
        self.service = service
    }

    func prepareNext(
        after sourceMessage: LearningMessage,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage {
        let historySignature = Self.historySignature(for: recentMessages)
        if queuedSourceID == sourceMessage.id,
           queuedModeID == languageMode.id,
           queuedHistorySignature == historySignature,
           let queuedNext {
            return queuedNext
        }

        if inFlightSourceID == sourceMessage.id,
           inFlightModeID == languageMode.id,
           inFlightHistorySignature == historySignature,
           let inFlightNext,
           let inFlightID {
            return try await finish(task: inFlightNext, id: inFlightID)
        }

        reset()
        let generationID = UUID()
        let task = Task {
            try await service.randomMessage(
                after: sourceMessage,
                languageMode: languageMode,
                recentMessages: recentMessages
            )
        }
        inFlightNext = task
        inFlightSourceID = sourceMessage.id
        inFlightModeID = languageMode.id
        inFlightHistorySignature = historySignature
        inFlightID = generationID

        return try await finish(task: task, id: generationID)
    }

    func consumeNext(
        after sourceMessage: LearningMessage,
        languageMode: LanguageMode,
        recentMessages: [LearningMessage]
    ) async throws -> LearningMessage {
        let historySignature = Self.historySignature(for: recentMessages)
        if queuedSourceID == sourceMessage.id,
           queuedModeID == languageMode.id,
           queuedHistorySignature == historySignature,
           let queuedNext {
            reset()
            return queuedNext
        }

        let nextMessage = try await prepareNext(
            after: sourceMessage,
            languageMode: languageMode,
            recentMessages: recentMessages
        )
        if queuedSourceID == sourceMessage.id,
           queuedModeID == languageMode.id,
           queuedHistorySignature == historySignature {
            reset()
        }
        return nextMessage
    }

    /// A delayed startup/language-change reset must not cancel work already
    /// requested for the new visible source.
    func reset(unlessFor sourceID: UUID) {
        guard inFlightSourceID != sourceID, queuedSourceID != sourceID else { return }
        reset()
    }

    func reset() {
        inFlightNext?.cancel()
        inFlightNext = nil
        inFlightSourceID = nil
        inFlightModeID = nil
        inFlightHistorySignature = nil
        inFlightID = nil
        queuedNext = nil
        queuedSourceID = nil
        queuedModeID = nil
        queuedHistorySignature = nil
    }

    private func finish(task: Task<LearningMessage, Error>, id: UUID) async throws -> LearningMessage {
        do {
            let nextMessage = try await task.value
            if inFlightID == id {
                queuedNext = nextMessage
                queuedSourceID = inFlightSourceID
                queuedModeID = inFlightModeID
                queuedHistorySignature = inFlightHistorySignature
                inFlightNext = nil
                inFlightSourceID = nil
                inFlightModeID = nil
                inFlightHistorySignature = nil
                inFlightID = nil
            }
            return nextMessage
        } catch {
            if inFlightID == id {
                inFlightNext = nil
                inFlightSourceID = nil
                inFlightModeID = nil
                inFlightHistorySignature = nil
                inFlightID = nil
            }
            throw error
        }
    }

    private static func historySignature(for messages: [LearningMessage]) -> String {
        messages.map(\.id.uuidString).joined(separator: "|")
    }
}
