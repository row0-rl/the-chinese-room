import Foundation
import SwiftData

@Model
final class MessageSessionRecord {
    @Attribute(.unique) var modeID: String
    var currentIndex: Int
    var messagesData: Data
    var updatedAt: Date

    init(modeID: String, currentIndex: Int, messages: [LearningMessage]) {
        self.modeID = modeID
        self.currentIndex = currentIndex
        self.messagesData = (try? JSONEncoder().encode(messages.map(PersistedMessage.init))) ?? Data()
        self.updatedAt = Date()
    }

    var messages: [LearningMessage] {
        guard let persistedMessages = try? JSONDecoder().decode([PersistedMessage].self, from: messagesData),
              !persistedMessages.isEmpty
        else {
            return [MockMessageService.openingMessage(for: LanguageCatalog.mode(id: modeID) ?? .defaultMode)]
        }

        return persistedMessages.map(\.learningMessage)
    }

    func update(messages: [LearningMessage], currentIndex: Int) {
        self.messagesData = (try? JSONEncoder().encode(messages.map(PersistedMessage.init))) ?? messagesData
        self.currentIndex = currentIndex
        self.updatedAt = Date()
    }
}

private struct PersistedMessage: Codable {
    let id: UUID
    let sourceText: String
    let normalizedSourceText: String
    let targetText: String
    let literalMeaning: String
    let literalChunks: [PersistedLiteralChunk]
    let examples: [PersistedExample]?

    init(_ message: LearningMessage) {
        self.id = message.id
        self.sourceText = message.sourceText
        self.normalizedSourceText = message.normalizedSourceText
        self.targetText = message.targetText
        self.literalMeaning = message.literalMeaning
        self.literalChunks = message.literalChunks.map(PersistedLiteralChunk.init)
        self.examples = message.examples?.map(PersistedExample.init)
    }

    var learningMessage: LearningMessage {
        LearningMessage(
            id: id,
            sourceText: sourceText,
            normalizedSourceText: normalizedSourceText,
            targetText: targetText,
            literalMeaning: literalMeaning,
            literalChunks: literalChunks.map(\.literalChunk),
            examples: examples?.map(\.example),
            audioState: .notLoaded
        )
    }
}

private struct PersistedLiteralChunk: Codable {
    let targetText: String
    let literalText: String

    init(_ chunk: MessageLiteralChunk) {
        self.targetText = chunk.targetText
        self.literalText = chunk.literalText
    }

    var literalChunk: MessageLiteralChunk {
        MessageLiteralChunk(targetText: targetText, literalText: literalText)
    }
}

private struct PersistedExample: Codable {
    let sourceText: String
    let targetText: String

    init(_ example: MessageExample) {
        self.sourceText = example.sourceText
        self.targetText = example.targetText
    }

    var example: MessageExample {
        MessageExample(sourceText: sourceText, targetText: targetText)
    }
}
