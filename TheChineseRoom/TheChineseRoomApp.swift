import SwiftUI
import SwiftData

@main
struct TheChineseRoomApp: App {
    var body: some Scene {
        WindowGroup {
            AppView()
        }
        .modelContainer(for: MessageSessionRecord.self)
    }
}
