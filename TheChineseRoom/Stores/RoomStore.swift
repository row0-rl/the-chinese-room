import Foundation
import SwiftData

@MainActor
@Observable
final class RoomStore {
    private(set) var rooms: [RoomRecord] = []
    private(set) var currentRoomID: String?
    private(set) var isLoaded = false
    private(set) var persistenceError: String?
    private var modelContext: ModelContext?
    // Snapshot recency at launch; selecting a room keeps the settings list in place.
    private var tabOrder: [String] = []

    var currentRoom: RoomRecord? { rooms.first { $0.modeID == currentRoomID && !$0.isArchived } }

    var activeRooms: [RoomRecord] {
        let active = tabOrder.compactMap { id in rooms.first { $0.modeID == id && !$0.isArchived && $0.languageMode != nil } }
        return active.filter(\.isPinned) + active.filter { !$0.isPinned }
    }

    var archivedRooms: [RoomRecord] {
        rooms.filter { $0.isArchived && $0.languageMode != nil }.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func attachPersistence(_ context: ModelContext, selectedMode: LanguageMode?) {
        guard !isLoaded else { return }
        modelContext = context
        do {
            rooms = try context.fetch(FetchDescriptor<RoomRecord>())
            // Upgrade existing pair histories without rewriting or deleting messages.
            let sessions = try context.fetch(FetchDescriptor<MessageSessionRecord>())
            for session in sessions where !rooms.contains(where: { $0.modeID == session.modeID }) {
                guard let mode = LanguageCatalog.mode(id: session.modeID) else { continue }
                insert(mode, lastUsedAt: session.updatedAt)
            }
            if let selectedMode, selectedMode.hasDistinctLanguages,
               !rooms.contains(where: { $0.modeID == selectedMode.id }) {
                insert(selectedMode)
            }
            tabOrder = rooms.sorted {
                if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
                return $0.modeID < $1.modeID
            }.map(\.modeID)
            currentRoomID = activeRooms.first { $0.modeID == selectedMode?.id }?.modeID ?? activeRooms.first?.modeID
            if let currentRoom { currentRoom.lastUsedAt = Date() }
            save()
        } catch {
            persistenceError = error.localizedDescription
        }
        isLoaded = true
    }

    /// Adding the same pair reopens its existing room, including archived rooms.
    @discardableResult
    func add(_ mode: LanguageMode) -> RoomRecord? {
        guard mode.hasDistinctLanguages else { return nil }
        let room = rooms.first { $0.modeID == mode.id } ?? insert(mode)
        select(room)
        return room
    }

    func select(_ room: RoomRecord) {
        guard rooms.contains(where: { $0 === room }), let mode = room.languageMode else { return }
        room.isArchived = false
        if !tabOrder.contains(room.modeID) { tabOrder.append(room.modeID) }
        room.lastUsedAt = Date()
        currentRoomID = room.modeID
        LanguageModeStorage.save(mode)
        save()
    }

    func togglePin(_ room: RoomRecord) {
        room.isPinned.toggle()
        save()
    }

    func rename(_ room: RoomRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        room.customName = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func archive(_ room: RoomRecord) {
        room.isArchived = true
        if currentRoomID == room.modeID {
            currentRoomID = nil
            if let next = activeRooms.first { select(next) }
        }
        save()
    }

    @discardableResult
    private func insert(_ mode: LanguageMode, lastUsedAt: Date = Date()) -> RoomRecord {
        let room = RoomRecord(mode: mode, lastUsedAt: lastUsedAt)
        rooms.append(room)
        tabOrder.append(room.modeID)
        modelContext?.insert(room)
        return room
    }

    private func save() {
        do {
            try modelContext?.save()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }
}
