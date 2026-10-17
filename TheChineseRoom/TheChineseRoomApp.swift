import SwiftUI
import SwiftData

@main
struct TheChineseRoomApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    init() {
        AppAppearance.consumeLaunchOverride()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--paper-fold-preview") {
                MessagePaperFoldPreview()
                    .appAppearance(appearance)
            } else if ProcessInfo.processInfo.arguments.contains("--dictation-smoke-test") {
                Text("Checking microphone startup…")
                    .task { await SystemDictationService.runSmokeTest() }
            } else if ProcessInfo.processInfo.arguments.contains("--speech-smoke-test") {
                Text("Running on-device speech checks…")
                    .task { await OnDeviceSpeechService.runSmokeTest() }
            } else {
                AppView()
                    .appAppearance(appearance)
            }
            #else
            AppView()
                .appAppearance(appearance)
            #endif
        }
        .modelContainer(for: [MessageSessionRecord.self, RoomRecord.self])
    }
}
