import Foundation
import SwiftData

// Replace device-only adapters while exercising the actual stores and SwiftData schema.
enum AppAppearance { case system, light, dark }
typealias OnDeviceSpeechService = SilentSpeechService
typealias SystemDictationService = UnavailableDictationService
typealias FoundationModelsMessageService = MockMessageService
extension MockMessageService {
    init(runtime: AppleMessageRuntime, translator: any TextTranslationService) { self.init() }
}
struct AppleMessageRuntime {
    static func availabilityMessage(languages: [LanguageProfile]) -> String? { nil }
}

@main struct RoomsRegression {
    @MainActor static func main() async throws {
        let defaults = UserDefaults.standard
        let previousSelection = defaults.string(forKey: "current_language_mode_id")
        defer {
            if let previousSelection { defaults.set(previousSelection, forKey: "current_language_mode_id") }
            else { defaults.removeObject(forKey: "current_language_mode_id") }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rooms.store")
        let french = LanguageMode.defaultMode
        let reverse = LanguageMode(source: french.target, target: french.source)
        let japanese = LanguageMode(source: LanguageCatalog.englishUS,
            target: LanguageCatalog.japaneseJapan)
        let first = MockMessageService.openingMessage(for: french)
        let second = LearningMessage(sourceText: "hello", normalizedSourceText: "hello",
            targetText: "bonjour", literalMeaning: "hello")

        // Open a real legacy store using the old, single-entity schema first.
        try seedLegacyStore(url: url, mode: french, messages: [first, second])
        let (japaneseID, reverseID) = try await exerciseUpgrade(url: url, french: french,
            reverse: reverse, japanese: japanese, first: first, second: second)
        // A new container validates that metadata and histories survive a process restart.
        let reloaded = try ModelContainer(for: MessageSessionRecord.self, RoomRecord.self,
            configurations: ModelConfiguration(url: url))
        let rooms = RoomStore()
        rooms.attachPersistence(reloaded.mainContext, selectedMode: japanese)
        precondition(rooms.persistenceError == nil)
        precondition(rooms.currentRoomID == japaneseID)
        precondition(rooms.currentRoom?.customName == "Tokyo trip")
        precondition(rooms.currentRoom?.isPinned == true)
        precondition(rooms.activeRooms.first?.modeID == japaneseID)
        precondition(rooms.archivedRooms.map(\.modeID) == [reverseID])
        precondition(rooms.rooms.count == 3, "Migration and relaunch must not duplicate rooms")

        let messages = MessageStore(service: MockMessageService(), persistsMessageHistory: true,
            initialLanguageMode: japanese)
        messages.attachPersistence(reloaded.mainContext)
        messages.updateLanguageMode(french)
        precondition(messages.messages.map(\.id) == [first.id, second.id])
        precondition(messages.currentIndex == 0, "Each room restores its own card position")
        messages.updateLanguageMode(reverse)
        precondition(messages.messages.count == 1)
        precondition(messages.currentMessage.id != first.id, "Reverse pairs have separate histories")
        messages.updateLanguageMode(french)
        precondition(messages.currentMessage.id == first.id)
        print("PASS: legacy schema upgrade, room metadata, selection, archive state, and independent histories survive reopening")

        // A stale selection of an archived room must not silently unarchive it on launch.
        let archivedSelection = RoomStore()
        archivedSelection.attachPersistence(reloaded.mainContext, selectedMode: reverse)
        precondition(archivedSelection.currentRoomID != reverseID)
        precondition(archivedSelection.archivedRooms.count == 1)
        for room in archivedSelection.activeRooms { archivedSelection.archive(room) }
        precondition(archivedSelection.currentRoom == nil && archivedSelection.activeRooms.isEmpty)
        let emptyLaunch = RoomStore()
        emptyLaunch.attachPersistence(reloaded.mainContext, selectedMode: french)
        precondition(emptyLaunch.currentRoom == nil, "Archiving the last room should reopen setup")
        precondition(emptyLaunch.archivedRooms.count == 3)
        let reopened = emptyLaunch.add(french)
        precondition(reopened != nil && emptyLaunch.currentRoomID == french.id)
        precondition(emptyLaunch.rooms.count == 3, "Readding an archived pair restores its existing room")
        let record = try reloaded.mainContext.fetch(FetchDescriptor<MessageSessionRecord>())
            .first { $0.modeID == french.id }
        precondition(record?.messages.map(\.id) == [first.id, second.id], "Archive and restore never delete history")
        print("PASS: archive-all, fresh launch with archived selection, and restore preserve existing messages")

        let freshContainer = try ModelContainer(for: MessageSessionRecord.self, RoomRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let fresh = RoomStore()
        fresh.attachPersistence(freshContainer.mainContext, selectedMode: nil)
        precondition(fresh.isLoaded && fresh.currentRoom == nil && fresh.rooms.isEmpty)
        precondition(fresh.add(LanguageMode(source: french.source, target: french.source)) == nil)
        precondition(fresh.rooms.isEmpty, "The store must reject same-language pairs, independently of UI")
        fresh.add(french)
        precondition(fresh.currentRoomID == french.id && fresh.rooms.count == 1)
        print("PASS: first-room creation and same-language rejection")

        for language in LanguageCatalog.supportedLanguages {
            let invalid = LanguageMode(source: language, target: language)
            precondition(LanguageCatalog.mode(id: invalid.id) == nil, "Same-language pair IDs must not restore")
            precondition(fresh.add(invalid) == nil)
            messages.updateLanguageMode(invalid)
            precondition(messages.currentLanguageMode == french, "Invalid pair changes must leave the current session intact")
        }
        let renamedEnglish = LanguageProfile(id: french.source.id, displayName: "Renamed English",
            nativeName: french.source.nativeName, promptName: french.source.promptName,
            localeIdentifier: french.source.localeIdentifier)
        precondition(fresh.add(LanguageMode(source: french.source, target: renamedEnglish)) == nil,
            "Language identity comes from its ID, not its display metadata")
        precondition(fresh.rooms.count == 1 && fresh.currentRoomID == french.id)

        // Previously stored invalid rooms must not be selectable or restored from the archive.
        let invalidMode = LanguageMode(source: french.source, target: french.source)
        let invalidRoom = RoomRecord(mode: invalidMode)
        freshContainer.mainContext.insert(invalidRoom)
        freshContainer.mainContext.insert(MessageSessionRecord(modeID: invalidMode.id, currentIndex: 0, messages: [first]))
        try freshContainer.mainContext.save()
        let invalidLaunch = RoomStore()
        invalidLaunch.attachPersistence(freshContainer.mainContext, selectedMode: invalidMode)
        precondition(invalidLaunch.currentRoomID == french.id && invalidLaunch.activeRooms.count == 1)
        invalidLaunch.select(invalidRoom)
        precondition(invalidLaunch.currentRoomID == french.id)
        invalidLaunch.archive(invalidRoom)
        precondition(invalidLaunch.archivedRooms.isEmpty)
        let preservedSessions = try freshContainer.mainContext.fetch(FetchDescriptor<MessageSessionRecord>())
        precondition(preservedSessions.count == 1,
            "Hiding invalid rooms must preserve stored history")
        print("PASS: every same-language pair, matching IDs with different metadata, and persisted invalid rooms are rejected")
    }

    @MainActor private static func seedLegacyStore(url: URL, mode: LanguageMode, messages: [LearningMessage]) throws {
        let legacy = try ModelContainer(for: MessageSessionRecord.self, configurations: ModelConfiguration(url: url))
        legacy.mainContext.insert(MessageSessionRecord(modeID: mode.id, currentIndex: 0, messages: messages))
        try legacy.mainContext.save()
    }

    @MainActor private static func exerciseUpgrade(url: URL, french: LanguageMode, reverse: LanguageMode,
        japanese: LanguageMode, first: LearningMessage, second: LearningMessage) async throws -> (String, String) {
        let container = try ModelContainer(for: MessageSessionRecord.self, RoomRecord.self,
            configurations: ModelConfiguration(url: url))
        let rooms = RoomStore()
        rooms.attachPersistence(container.mainContext, selectedMode: french)
        precondition(rooms.persistenceError == nil)
        precondition(rooms.rooms.count == 1 && rooms.currentRoomID == french.id)
        let originalData = try container.mainContext.fetch(FetchDescriptor<MessageSessionRecord>()).first!.messagesData
        let frenchRoom = rooms.currentRoom!
        precondition(rooms.add(french) === frenchRoom)
        let reverseRoom = rooms.add(reverse)!
        let japaneseRoom = rooms.add(japanese)!
        let initialOrder = rooms.activeRooms.map(\.modeID)
        rooms.select(reverseRoom)
        rooms.select(frenchRoom)
        precondition(rooms.activeRooms.map(\.modeID) == initialOrder, "Selecting tabs must not reorder them")
        rooms.togglePin(japaneseRoom)
        precondition(rooms.activeRooms.first === japaneseRoom)
        rooms.rename(japaneseRoom, to: "  Tokyo trip \n")
        precondition(japaneseRoom.customName == "Tokyo trip")
        rooms.rename(frenchRoom, to: " \n")
        precondition(frenchRoom.customName == nil)
        rooms.archive(frenchRoom)
        precondition(rooms.currentRoomID == japanese.id, "Archiving the current room selects a remaining tab")
        rooms.add(french)
        precondition(rooms.currentRoom === frenchRoom && rooms.rooms.count == 3)
        rooms.archive(reverseRoom)
        rooms.select(japaneseRoom)
        precondition(rooms.activeRooms.map(\.modeID) == [japanese.id, french.id])
        // Give the unpinned room a newer timestamp: pinning still takes precedence on launch.
        frenchRoom.lastUsedAt = Date().addingTimeInterval(60)
        try container.mainContext.save()
        let after = try container.mainContext.fetch(FetchDescriptor<MessageSessionRecord>()).first!
        precondition(after.messagesData == originalData && after.currentIndex == 0,
            "Room operations must preserve the exact legacy message payload")
        print("PASS: duplicate prevention, directional pairs, stable tabs, pinning, rename, and archive fallback")

        let store = MessageStore(service: MockMessageService(), persistsMessageHistory: true, initialLanguageMode: french)
        store.attachPersistence(container.mainContext)
        precondition(store.messages.map(\.id) == [first.id, second.id])
        await store.nextRandomMessage() // Move through existing history without generation.
        precondition(store.currentMessage.id == second.id && store.currentIndex == 1)
        store.updateLanguageMode(japanese)
        store.updateLanguageMode(french)
        precondition(store.currentMessage.id == second.id && store.currentIndex == 1)
        store.previousMessage()
        precondition(store.currentIndex == 0)
        return (japaneseRoom.modeID, reverseRoom.modeID)
    }
}
