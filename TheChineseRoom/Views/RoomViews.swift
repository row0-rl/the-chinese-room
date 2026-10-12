import SwiftUI

struct RoomLabel: View {
    let room: RoomRecord
    let strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(room.title(strings: strings)).appFont(.body)
            if room.customName != nil {
                Text(room.pairLabel(strings: strings)).appFont(.caption).opacity(0.7)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: 240, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private struct RoomActions: View {
    let rooms: RoomStore
    let room: RoomRecord
    let strings: AppStrings
    let onRename: () -> Void

    var body: some View {
        Button(room.isPinned ? strings.unpinRoomTitle : strings.pinRoomTitle,
               systemImage: room.isPinned ? "pin.slash" : "pin") { rooms.togglePin(room) }
        Button(strings.renameRoomTitle, systemImage: "pencil", action: onRename)
        Button(strings.archiveRoomTitle, systemImage: "archivebox") { rooms.archive(room) }
    }
}

struct RoomCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let rooms: RoomStore
    let isFirstRoom: Bool
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    private var strings: AppStrings { AppLocale.forLanguage(source).strings }
    private var mode: LanguageMode { LanguageMode(source: source, target: target) }
    private var existingRoom: RoomRecord? { rooms.rooms.first { $0.modeID == mode.id } }

    init(rooms: RoomStore, initialMode: LanguageMode, isFirstRoom: Bool = false) {
        self.rooms = rooms
        self.isFirstRoom = isFirstRoom
        _source = State(initialValue: initialMode.source)
        // Start with an uncreated pair when opening Add, retaining the language you learn through.
        let nextTarget = LanguageCatalog.supportedLanguages.first { language in
            language.id != initialMode.source.id && !rooms.rooms.contains(where: { $0.modeID == LanguageMode(source: initialMode.source, target: language).id })
        }
        let fallbackTarget = initialMode.target.id != initialMode.source.id ? initialMode.target
            : LanguageCatalog.supportedLanguages.first { $0.id != initialMode.source.id }!
        _target = State(initialValue: isFirstRoom ? fallbackTarget : (nextTarget ?? fallbackTarget))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(strings.roomCreationSubtitle).appFont(.body)
                }
                .listRowBackground(Color.chineseRoomCard)
                Section {
                    languagePicker(strings.roomTargetTitle, selection: $target, excluding: source)
                    languagePicker(strings.roomSourceTitle, selection: $source, excluding: target)
                } footer: {
                    if source.id == target.id {
                        Text(strings.roomDifferentLanguages).appFont(.footnote)
                    } else if existingRoom != nil {
                        Text(strings.roomAlreadyExists).appFont(.footnote)
                    }
                }
                .listRowBackground(Color.chineseRoomCard)
                Section {
                    Button(existingRoom == nil ? strings.createRoomTitle : strings.openRoomTitle) {
                        guard rooms.add(mode) != nil else { return }
                        if !isFirstRoom { dismiss() }
                    }
                    .appFont(.headline)
                    .disabled(source.id == target.id)
                    .accessibilityIdentifier("create-room")
                }
                .listRowBackground(Color.chineseRoomCard)
                if !rooms.archivedRooms.isEmpty {
                    Section {
                        ForEach(rooms.archivedRooms) { room in
                            Button {
                                rooms.select(room)
                                if !isFirstRoom { dismiss() }
                            } label: {
                                HStack {
                                    RoomLabel(room: room, strings: strings)
                                    Spacer()
                                    Image(systemName: "arrow.uturn.backward")
                                }
                            }
                        }
                    } header: {
                        Text(strings.archivedRoomsTitle).appFont(.footnote)
                    } footer: {
                        Text(strings.archivedRoomsFooter).appFont(.footnote)
                    }
                    .listRowBackground(Color.chineseRoomCard)
                }
                if let error = rooms.persistenceError {
                    Section { Text(error).appFont(.footnote).foregroundStyle(.red) }
                    .listRowBackground(Color.chineseRoomCard)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.chineseRoomBackground)
            .foregroundStyle(Color.chineseRoomInk)
            .tint(Color.chineseRoomInk)
            .navigationTitle(isFirstRoom ? (rooms.rooms.isEmpty ? strings.firstRoomTitle : strings.chooseRoomTitle) : strings.addRoomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.locale, Locale(identifier: strings.localeIdentifier))
            .toolbar {
                if !isFirstRoom {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(strings.cancelButtonTitle) { dismiss() }.appFont(.body)
                    }
                }
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<LanguageProfile>, excluding other: LanguageProfile) -> some View {
        Picker(title, selection: selection) {
            ForEach(LanguageCatalog.supportedLanguages.filter { $0.id != other.id }) { language in
                let name = strings.roomLanguageName(language)
                Text(name == language.nativeName ? name : "\(name) · \(language.nativeName)")
                    .appFont(.body).tag(language)
            }
        }
        .appFont(.body)
    }
}

struct RoomsManagementView: View {
    let rooms: RoomStore
    let store: MessageStore
    @State private var showsAddRoom = false
    @State private var renamingRoom: RoomRecord?
    private var strings: AppStrings { AppLocale.forLanguage(store.currentLanguageMode.source).strings }
    private var canSwitch: Bool { !store.isGenerating && !store.isTranscribing }

    var body: some View {
        Form {
            Section {
                ForEach(rooms.activeRooms) { room in
                    Button { rooms.select(room) } label: {
                        HStack {
                            RoomLabel(room: room, strings: strings)
                            Spacer()
                            if room.isPinned { Image(systemName: "pin.fill") }
                            if rooms.currentRoomID == room.modeID { Image(systemName: "checkmark") }
                        }
                    }
                    .disabled(!canSwitch)
                    .contextMenu {
                        RoomActions(rooms: rooms, room: room, strings: strings) { renamingRoom = room }
                            .disabled(!canSwitch)
                    }
                }
                Button(strings.addRoomTitle, systemImage: "plus") { showsAddRoom = true }
                    .appFont(.body).disabled(!canSwitch)
            } footer: {
                Text(strings.roomsOrderingFooter).appFont(.footnote)
            }
            .listRowBackground(Color.chineseRoomCard)
            if !rooms.archivedRooms.isEmpty {
                Section {
                    ForEach(rooms.archivedRooms) { room in
                        Button { rooms.select(room) } label: {
                            HStack {
                                RoomLabel(room: room, strings: strings)
                                Spacer()
                                Image(systemName: "arrow.uturn.backward")
                            }
                        }
                        .disabled(!canSwitch)
                    }
                } header: {
                    Text(strings.archivedRoomsTitle).appFont(.footnote)
                } footer: {
                    Text(strings.archivedRoomsFooter).appFont(.footnote)
                }
                .listRowBackground(Color.chineseRoomCard)
            }
            if let error = rooms.persistenceError {
                Section { Text(error).appFont(.footnote).foregroundStyle(.red) }
                .listRowBackground(Color.chineseRoomCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.chineseRoomBackground)
        .foregroundStyle(Color.chineseRoomInk)
        .navigationTitle(strings.roomsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.chineseRoomInk)
        .sheet(isPresented: $showsAddRoom) {
            RoomCreationView(rooms: rooms, initialMode: store.currentLanguageMode)
        }
        .sheet(item: $renamingRoom) { room in
            RoomRenameView(rooms: rooms, room: room, strings: strings)
        }
    }
}

private struct RoomRenameView: View {
    @Environment(\.dismiss) private var dismiss
    let rooms: RoomStore
    let room: RoomRecord
    let strings: AppStrings
    @State private var name: String

    init(rooms: RoomStore, room: RoomRecord, strings: AppStrings) {
        self.rooms = rooms
        self.room = room
        self.strings = strings
        _name = State(initialValue: room.customName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(strings.roomNameTitle, text: $name).appFont(.body)
                        .accessibilityIdentifier("room-name")
                    Text(room.pairLabel(strings: strings)).appFont(.footnote)
                } footer: {
                    Text(strings.roomNameFooter).appFont(.footnote)
                }
                .listRowBackground(Color.chineseRoomCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.chineseRoomBackground)
            .foregroundStyle(Color.chineseRoomInk)
            .tint(Color.chineseRoomInk)
            .navigationTitle(strings.renameRoomTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(strings.cancelButtonTitle) { dismiss() }.appFont(.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.doneButtonTitle) {
                        rooms.rename(room, to: name)
                        dismiss()
                    }.appFont(.body)
                }
            }
        }
    }
}
