import Foundation
import CoreGraphics
import SwiftData

// Replace device-only adapters while exercising the actual stores and SwiftData schema.
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

        // Each saved collection receives only its Room's live history.
        var savedFirst = first; savedFirst.isSaved = true
        var savedSecond = second; savedSecond.isSaved = true
        let collection = SavedMessageCollection.items(modeID: french.id,
            messages: [first, savedSecond], roomTitle: "French")
        precondition(collection.count == 1 && collection[0].message.id == second.id)
        precondition(collection.allSatisfy { $0.modeID == french.id })
        let otherRoom = SavedMessageCollection.items(modeID: reverse.id,
            messages: [savedFirst], roomTitle: "Reverse")
        precondition(otherRoom.count == 1 && otherRoom[0].modeID == reverse.id)
        precondition(collection[0].id != otherRoom[0].id)
        let emptyRoom = SavedMessageCollection.items(modeID: japanese.id, messages: [first], roomTitle: "Japanese")
        precondition(emptyRoom.isEmpty, "Other Rooms' saves must not appear in an empty current Room")
        let afterUnsave = SavedMessageCollection.items(modeID: french.id, messages: [first, second], roomTitle: "French")
        precondition(afterUnsave.isEmpty)
        let newestFirst = SavedMessageCollection.items(modeID: french.id,
            messages: [savedFirst, savedSecond], roomTitle: "French")
        precondition(newestFirst.map { $0.message.id } == [second.id, first.id])
        print("PASS: saved collections are isolated per Room, follow live save state, and retain history order")

        let compactStack = SavedMessageStackLayout(count: 4, expandedIndex: nil, expandedHeight: 0)
        precondition(compactStack.height == 320 && compactStack.offset(at: 2) == 96)
        precondition(compactStack.index(at: 10) == nil && compactStack.index(at: -1) == nil)
        precondition(compactStack.index(at: 61) == 0 && compactStack.index(at: 62) == 1)
        let middlePeek = SavedMessageStackLayout(count: 4, expandedIndex: 1, expandedHeight: 340)
        precondition(middlePeek.offset(at: 1) == 48, "Expansion must keep the selected card's top in place")
        precondition(middlePeek.offset(at: 2) == 374 && middlePeek.height == 598)
        precondition(middlePeek.index(at: 370) == 1 && middlePeek.index(at: 388) == 2,
            "Scrubbing must hit the visible card after the lower stack moves")
        let lastPeek = SavedMessageStackLayout(count: 4, expandedIndex: 3, expandedHeight: 600)
        precondition(lastPeek.offset(at: 3) == 144 && lastPeek.height == 744)
        precondition(lastPeek.index(at: 743) == 3 && lastPeek.index(at: 744) == nil)
        let shortPeek = SavedMessageStackLayout(count: 1, expandedIndex: 0, expandedHeight: 20)
        precondition(shortPeek.height == 176)
        precondition(SavedMessageStackLayout(count: 0, expandedIndex: nil, expandedHeight: 0).height == 0)
        let fixedHeights: [CGFloat] = [260, 340, 210, 280]
        let intact = SavedMessageStackLayout(count: 4, expandedIndex: nil, expandedHeight: 0,
            cardHeights: fixedHeights)
        let reveal = SavedMessageStackLayout(count: 4, expandedIndex: 1, expandedHeight: 340,
            cardHeights: fixedHeights, anchorOffset: intact.offset(at: 1))
        let switchAnchor = reveal.offset(at: 2)
        let switched = SavedMessageStackLayout(count: 4, expandedIndex: 2, expandedHeight: 210,
            cardHeights: fixedHeights, anchorOffset: switchAnchor)
        for index in 0..<4 {
            precondition(intact.height(at: index) == reveal.height(at: index))
            precondition(reveal.height(at: index) == switched.height(at: index),
                "Covered and revealed cards must keep the same full paper size")
        }
        precondition(reveal.offset(at: 1) == intact.offset(at: 1))
        precondition(switched.offset(at: 2) == switchAnchor,
            "Scrubbing must preserve the newly selected sheet's current position")
        precondition(switched.index(at: switchAnchor + 30) == 2)
        precondition(switched.topOffset > 0 && switched.index(at: switched.topOffset - 1) == nil)
        precondition(switched.offset(at: 3) > reveal.offset(at: 3))
        for viewport in [CGRect(x: 0, y: 0, width: 360, height: 700),
                         CGRect(x: 0, y: 550, width: 360, height: 700)] {
            for index in 0..<4 {
                let fingerY = viewport.minY + viewport.height * 0.65
                let downAnchor = intact.selectionAnchor(at: index, verticalDelta: 15, fingerY: fingerY)
                let aligned = SavedMessageStackLayout(count: 4, expandedIndex: index,
                    expandedHeight: fixedHeights[index], cardHeights: fixedHeights, anchorOffset: downAnchor)
                precondition(abs(aligned.offset(at: index) + aligned.height(at: index)
                    - fingerY - SavedMessageStackLayout.fingerEdgeInset) < 0.001)
                precondition(aligned.index(at: fingerY + 1) == index,
                    "Small continued downward movement must remain inside the popped sheet")
                precondition(aligned.height(at: index) == intact.height(at: index))
                let upAnchor = intact.selectionAnchor(at: index, verticalDelta: -15, fingerY: fingerY)
                let upAligned = SavedMessageStackLayout(count: 4, expandedIndex: index,
                    expandedHeight: fixedHeights[index], cardHeights: fixedHeights, anchorOffset: upAnchor)
                precondition(abs(upAligned.offset(at: index) + SavedMessageStackLayout.topInset
                    + SavedMessageStackLayout.fingerEdgeInset - fingerY) < 0.001,
                    "Upward selection must place the visible top edge 28 points above the finger")
                precondition(upAligned.height(at: index) == intact.height(at: index))
                precondition(intact.selectionAnchor(at: index, verticalDelta: 0, fingerY: fingerY) == intact.offset(at: index))
                let next = min(3, index + 1)
                precondition(aligned.selectionAnchor(at: next, verticalDelta: -2, fingerY: fingerY)
                    == fingerY - SavedMessageStackLayout.fingerEdgeInset - SavedMessageStackLayout.topInset)
            }
        }
        var scrub = SavedMessageScrub()
        precondition(scrub.selection(after: 47, current: 1, count: 4) == nil)
        precondition(scrub.selection(after: 1, current: 1, count: 4) == 2)
        precondition(scrub.selection(after: 0, current: 2, count: 4) == nil)
        precondition(scrub.selection(after: -30, current: 2, count: 4) == nil)
        precondition(scrub.selection(after: 30, current: 2, count: 4) == nil)
        precondition(scrub.selection(after: -48, current: 2, count: 4) == 1)
        precondition(scrub.selection(after: 500, current: 1, count: 4) == 2,
            "One drag update must select only the adjacent card, without cascading")
        precondition(scrub.selection(after: 48, current: 3, count: 4) == nil)
        precondition(scrub.selection(after: -48, current: 3, count: 4) == 2)
        precondition(scrub.selection(after: -48, current: 0, count: 4) == nil)
        print("PASS: bidirectional scrub thresholds, direction reversal, endpoints, and adjacent-only selection")
        print("PASS: symmetric finger-edge spacing, upward reversal, fixed paper size, and scrolled coordinates")
        print("PASS: immutable paper heights and anchored selection while neighboring sheets move")
        print("PASS: one-card expansion, lower-stack displacement, visible-card scrub targeting, and collapse geometry")

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

        precondition(LearningLanguage.allCases.count == 11)
        precondition(Set(LanguageCatalog.allProfiles.map(\.id)).count == LanguageCatalog.allProfiles.count)
        for language in LearningLanguage.allCases {
            precondition(language.forms.count >= 2, "Every language needs an origin/form choice")
            precondition(language.forms.first == language.defaultProfile, "The preferred default must be first in the menu")
            let labels = language.forms.map { AppStrings(localeIdentifier: "en").originFormName($0) }
            precondition(Set(labels).count == labels.count, "Each form must have a distinct picker label")
            for form in language.forms {
                precondition(LanguageCatalog.language(id: form.id) == form)
                precondition(form.learningLanguage == language)
            }
        }
        let british = LanguageCatalog.language(id: "english_uk")!
        let mexican = LanguageCatalog.language(id: "spanish_mexico")!
        let chilean = LanguageCatalog.language(id: "spanish_chile")!
        let taiwanese = LanguageCatalog.language(id: "mandarin_taiwan")!
        let cantonese = LanguageCatalog.language(id: "cantonese_hong_kong")!
        let typicalPair = LanguageMode(source: british, target: chilean).defaultForms
        precondition(typicalPair == LanguageMode(source: LanguageCatalog.englishUS, target: mexican))
        precondition(mexican.needsRegionalAdaptation, "Changing the picker default must not skip Mexican wording adaptation")
        precondition(LanguageCatalog.mode(id: "english_us__to__spanish_spain")?.target == LanguageCatalog.spanishSpain,
            "The new Spanish default must preserve the meaning of legacy room IDs")
        precondition(!LanguageMode(source: french.source, target: british).hasDistinctLanguages)
        precondition(LanguageCatalog.mode(id: "english_us__to__english_uk") == nil)
        precondition(LanguageCatalog.mode(id: "spanish_spain__to__spanish_chile") == nil)
        precondition(LanguageCatalog.mode(id: "simplified_chinese__to__mandarin_taiwan") == nil)
        precondition(taiwanese.normalizedWriting("我饿了") == "我餓了")
        precondition(LanguageCatalog.simplifiedChinese.normalizedWriting("我餓了") == "我饿了")
        precondition(PronunciationNotationSystem.fixedSystem(for: taiwanese) == .pinyin)
        precondition(PronunciationNotationSystem.fixedSystem(for: cantonese) == .ipa)
        precondition(AppLocale.forLanguage(taiwanese).id == "zh-Hant")
        precondition(HanjaAnnotation.supports(LanguageMode(source: taiwanese, target: LanguageCatalog.koreanHangul)))
        precondition(cantonese.modelLocaleIdentifier == "zh-Hant-HK" && cantonese.translationLocaleIdentifier == "zh-HK")
        let chinesePair = LanguageMode(source: LanguageCatalog.simplifiedChinese, target: cantonese)
        precondition(chinesePair.defaultForms == chinesePair)
        let reverseChinesePair = LanguageMode(source: cantonese, target: taiwanese).defaultForms
        precondition(reverseChinesePair.source == cantonese && reverseChinesePair.target == LanguageCatalog.simplifiedChinese,
            "Defaults must retain the distinct Mandarin–Cantonese pairing")
        precondition(chinesePair.hasDistinctLanguages && chinesePair.requiresDirectChineseTransformation)
        precondition(LanguageCatalog.mode(id: chinesePair.id) == chinesePair)
        for group in LearningLanguage.allCases {
            for form in group.forms(excluding: british) { precondition(form.languageIdentity != "en") }
        }

        let regionalContainer = try ModelContainer(for: MessageSessionRecord.self, RoomRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let mexicoMode = LanguageMode(source: british, target: mexican)
        let chileMode = LanguageMode(source: british, target: chilean)
        let mexicoCard = MockMessageService.openingMessage(for: mexicoMode)
        let chileCard = MockMessageService.openingMessage(for: chileMode)
        regionalContainer.mainContext.insert(MessageSessionRecord(modeID: mexicoMode.id, currentIndex: 0, messages: [mexicoCard]))
        regionalContainer.mainContext.insert(MessageSessionRecord(modeID: chileMode.id, currentIndex: 0, messages: [chileCard]))
        try regionalContainer.mainContext.save()
        let regionalRooms = RoomStore()
        regionalRooms.attachPersistence(regionalContainer.mainContext, selectedMode: mexicoMode)
        precondition(regionalRooms.activeRooms.count == 2)
        precondition(regionalRooms.currentRoomID == mexicoMode.id)
        let strings = AppStrings(localeIdentifier: "en")
        precondition(regionalRooms.currentRoom!.pairLabel(strings: strings).contains("Mexico"))
        precondition(regionalRooms.add(mexicoMode) === regionalRooms.currentRoom)
        precondition(regionalRooms.add(LanguageMode(source: mexican, target: chilean)) == nil)
        let regionalMessages = MessageStore(service: MockMessageService(), persistsMessageHistory: true, initialLanguageMode: mexicoMode)
        regionalMessages.attachPersistence(regionalContainer.mainContext)
        precondition(regionalMessages.currentMessage.id == mexicoCard.id)
        regionalMessages.updateLanguageMode(chileMode)
        precondition(regionalMessages.currentMessage.id == chileCard.id)
        regionalMessages.updateLanguageMode(mexicoMode)
        precondition(regionalMessages.currentMessage.id == mexicoCard.id)
        print("PASS: form catalog, same-language exclusions, Chinese identities/scripts, origin labels, and isolated regional histories")
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
