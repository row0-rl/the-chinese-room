import SwiftUI
import SwiftData
import Translation

struct AppView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: MessageStore
    @State private var rooms = RoomStore()
    @State private var showsLaunchTitle = true
    @State private var hasFinishedLaunch = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var appLocale: AppLocale { AppLocale.forLanguage(store.currentLanguageMode.source) }

    init() {
        let savedMode = LanguageModeStorage.currentMode
        let initialMode = savedMode ?? .defaultMode
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--rooms-preview") {
            _store = State(initialValue: MessageStore(service: RoomPreviewMessageService(),
                persistsMessageHistory: true, initialLanguageMode: initialMode))
            return
        }
        #endif
        _store = State(initialValue: MessageStore(configuration: .current, initialLanguageMode: initialMode))
    }

    var body: some View {
        Group {
            if !rooms.isLoaded {
                Color.chineseRoomBackground.ignoresSafeArea()
            } else if rooms.currentRoom == nil {
                RoomCreationView(rooms: rooms, initialMode: store.currentLanguageMode, isFirstRoom: true)
            } else {
                MessageHomeView(store: store, rooms: rooms, appStrings: appLocale.strings)
            }
        }
        .appFont(.body)
        .background {
            if let translator = store.appleTranslation {
                AppleTranslationHost(translator: translator)
            }
        }
        .environment(\.locale, Locale(identifier: appLocale.id))
        .onAppear {
            rooms.attachPersistence(modelContext, selectedMode: LanguageModeStorage.currentMode)
            activateCurrentRoom()
        }
        .onChange(of: rooms.currentRoomID) { _, _ in activateCurrentRoom() }
        .appClock()
        .allowsHitTesting(!showsLaunchTitle)
        .accessibilityHidden(showsLaunchTitle)
        .overlay {
            if showsLaunchTitle {
                LaunchTitleView {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25), completionCriteria: .removed) {
                        showsLaunchTitle = false
                    } completion: {
                        hasFinishedLaunch = true
                    }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: hasFinishedLaunch && rooms.currentRoom != nil && scenePhase == .active) { _, ready in
            if ready { store.enableAutomaticSpeech() }
        }
    }

    private func activateCurrentRoom() {
        guard let mode = rooms.currentRoom?.languageMode else {
            store.deactivateCurrentRoom()
            return
        }
        store.updateLanguageMode(mode)
        store.attachPersistence(modelContext)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--rooms-preview") {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--saved-message-preview"), !store.currentMessage.isSaved {
                store.toggleSaved(for: store.currentMessage.id)
            } else if arguments.contains("--unsaved-message-preview"), store.currentMessage.isSaved {
                store.toggleSaved(for: store.currentMessage.id)
            }
        }
        #endif
    }
}

#Preview {
    AppView()
}

#if DEBUG
/// Layout checks without launching Translation downloads or device-only speech.
private struct RoomPreviewMessageService: MessageService {
    func randomMessage(after: LearningMessage?, languageMode: LanguageMode, recentMessages: [LearningMessage]) async throws -> LearningMessage {
        throw CancellationError()
    }

    func message(for input: String, languageMode: LanguageMode) async throws -> LearningMessage {
        throw CancellationError()
    }
}
#endif

private struct AppleTranslationHost: View {
    let translator: AppleTranslationService

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .background {
                if let request = translator.currentRequest {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .translationTask(
                            source: Locale.Language(identifier: request.languageMode.source.translationLocaleIdentifier),
                            target: Locale.Language(identifier: request.languageMode.target.translationLocaleIdentifier)
                        ) { session in
                            await translator.perform(request, using: session)
                        }
                        .id(request.id)
                }
            }
            .onDisappear { translator.cancelAll() }
    }
}
