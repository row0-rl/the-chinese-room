import SwiftUI

/// The same pre-rendered PencilKit lettering as the system launch screen.
/// Revealing the cached image avoids doing ink rasterization during startup.
struct LaunchTitleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    let onFinished: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, min(320, geometry.size.width - 48))
            ZStack {
                Color.chineseRoomBackground
                ZStack(alignment: .leading) {
                    title.opacity(0.14)
                    title.mask(alignment: .leading) {
                        Rectangle().frame(width: width * progress)
                    }
                }
                .frame(width: width, height: width / 4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The Chinese Room")
        .task {
            if reduceMotion {
                progress = 1
            } else {
                withAnimation(.linear(duration: 1.4)) { progress = 1 }
                do { try await Task.sleep(for: .milliseconds(1600)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }

    private var title: some View {
        Image("PencilLaunchTitle")
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(Color.chineseRoomInk)
            .accessibilityHidden(true)
    }
}
