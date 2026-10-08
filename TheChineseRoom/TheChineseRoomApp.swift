import SwiftUI
import SwiftData

@main
struct TheChineseRoomApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system

    init() {
        AppFont.configureNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--dictation-smoke-test") {
                Text("Checking microphone startup…")
                    .task { await SystemDictationService.runSmokeTest() }
            } else if ProcessInfo.processInfo.arguments.contains("--speech-smoke-test") {
                Text("Running on-device speech checks…")
                    .task { await OnDeviceSpeechService.runSmokeTest() }
            } else {
                AppView()
                    .preferredColorScheme(appearance.colorScheme)
            }
            #else
            AppView()
                .preferredColorScheme(appearance.colorScheme)
            #endif
        }
        .modelContainer(for: MessageSessionRecord.self)
    }
}
