import SwiftUI
import UIKit

/// An app-owned clock; iOS only exposes visibility and light/dark status bar styling.
struct AppClock: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var refreshID = 0

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime
                .hour(.defaultDigits(amPM: .omitted))
                .minute()
                .locale(.autoupdatingCurrent))
                .font(.custom(AppFont.name, fixedSize: 20))
                .foregroundStyle(.black)
                .fixedSize()
                .accessibilityLabel(Text(context.date, format: .dateTime
                    .hour().minute().locale(.autoupdatingCurrent)))
        }
        .id(refreshID)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshID &+= 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            refreshID &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
            refreshID &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            refreshID &+= 1
        }
    }
}

extension View {
    func appClock() -> some View {
        modifier(AppClockModifier())
    }
}

private struct AppClockModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            let hasTallTopInset = topInset > 30
            let clockHeight = max(28, topInset)
            // Flat-top phones and landscape windows need their own header space.
            // On a notched phone, use the existing safe area above the content.
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: max(0, clockHeight - topInset))
                }
                .overlay(alignment: .topLeading) {
                    AppClock()
                        .frame(width: 80, height: clockHeight,
                               alignment: hasTallTopInset ? .center : .leading)
                        .padding(.leading, hasTallTopInset ? 24 : 16)
                        .offset(y: -topInset + (hasTallTopInset ? 6 : 0))
                        .allowsHitTesting(false)
                }
        }
        .toolbarVisibility(.hidden, for: .statusBar)
    }
}
