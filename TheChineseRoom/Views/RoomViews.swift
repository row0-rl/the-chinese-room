import SwiftUI

struct RoomLabel: View {
    let room: RoomRecord
    let strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(room.title(strings: strings)).font(.body).lineLimit(room.customName == nil ? 3 : 2)
            if room.customName != nil {
                Text(room.pairLabel(strings: strings)).font(.caption).opacity(0.7).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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
        let defaults = initialMode.defaultForms
        _source = State(initialValue: defaults.source)
        _target = State(initialValue: defaults.target)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(strings.roomCreationSubtitle).font(.body)
                }
                .listRowBackground(Color.chineseRoomCard)
                Section {
                    languagePicker(strings.roomTargetTitle, selection: $target, excluding: source)
                    formPicker(selection: $target, excluding: source)
                } footer: {
                    Text(strings.originFormFooter).font(.footnote)
                }
                .listRowBackground(Color.chineseRoomCard)
                Section {
                    languagePicker(strings.roomSourceTitle, selection: $source, excluding: target)
                    formPicker(selection: $source, excluding: target)
                } footer: {
                    if !mode.hasDistinctLanguages {
                        Text(strings.roomDifferentLanguages).font(.footnote)
                    } else if existingRoom != nil {
                        Text(strings.roomAlreadyExists).font(.footnote)
                    }
                }
                .listRowBackground(Color.chineseRoomCard)
                Section {
                    Button(existingRoom == nil ? strings.createRoomTitle : strings.openRoomTitle) {
                        guard rooms.add(mode) != nil else { return }
                        if !isFirstRoom { dismiss() }
                    }
                    .font(.headline)
                    .disabled(!mode.hasDistinctLanguages)
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
                        Text(strings.archivedRoomsTitle).font(.footnote)
                    } footer: {
                        Text(strings.archivedRoomsFooter).font(.footnote)
                    }
                    .listRowBackground(Color.chineseRoomCard)
                }
                if let error = rooms.persistenceError {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
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
                        Button(strings.cancelButtonTitle) { dismiss() }.font(.body)
                    }
                }
            }
        }
    }

    private func languagePicker(_ title: String, selection: Binding<LanguageProfile>, excluding other: LanguageProfile) -> some View {
        let selectedLanguage = Binding<LearningLanguage>(
            get: { selection.wrappedValue.learningLanguage },
            set: { language in
                guard language != selection.wrappedValue.learningLanguage,
                      let form = language.defaultForm(excluding: other) else { return }
                selection.wrappedValue = form
            }
        )
        return Picker(title, selection: selectedLanguage) {
            ForEach(LearningLanguage.allCases.filter { !$0.forms(excluding: other).isEmpty }) { language in
                let name = strings.languageGroupName(language)
                let nativeName = language == .chinese ? "中文" : language.defaultProfile.nativeName
                Text(name == nativeName ? name : "\(name) · \(nativeName)")
                    .font(.body).tag(language)
            }
        }
        .font(.body)
    }

    private func formPicker(selection: Binding<LanguageProfile>, excluding other: LanguageProfile) -> some View {
        Picker(strings.originFormTitle, selection: selection) {
            ForEach(selection.wrappedValue.learningLanguage.forms(excluding: other)) { form in
                Text(strings.originFormName(form)).font(.body).tag(form)
            }
        }
        .font(.body)
        .accessibilityIdentifier(selection.wrappedValue.id == target.id ? "target-origin-form" : "source-origin-form")
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
                    .font(.body).disabled(!canSwitch)
            } footer: {
                Text(strings.roomsOrderingFooter).font(.footnote)
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
                    Text(strings.archivedRoomsTitle).font(.footnote)
                } footer: {
                    Text(strings.archivedRoomsFooter).font(.footnote)
                }
                .listRowBackground(Color.chineseRoomCard)
            }
            if let error = rooms.persistenceError {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
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
                    TextField(strings.roomNameTitle, text: $name).font(.body)
                        .accessibilityIdentifier("room-name")
                    Text(room.pairLabel(strings: strings)).font(.footnote)
                } footer: {
                    Text(strings.roomNameFooter).font(.footnote)
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
                    Button(strings.cancelButtonTitle) { dismiss() }.font(.body)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(strings.doneButtonTitle) {
                        rooms.rename(room, to: name)
                        dismiss()
                    }.font(.body)
                }
            }
        }
    }
}
