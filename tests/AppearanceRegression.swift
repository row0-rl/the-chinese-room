import SwiftUI
import UIKit

/// A separate simulator app tests the production window override with a real
/// SwiftUI sheet. Its UserDefaults domain is isolated from The Chinese Room.
@main struct AppearanceRegressionApp: App {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var state = AppearanceRegressionState()

    init() {
        AppAppearance.consumeLaunchOverride()
    }

    var body: some Scene {
        WindowGroup {
            AppearanceProbe(state: state, isSheet: false)
                .appAppearance(appearance)
                .sheet(isPresented: $state.showsSettings) {
                    AppearanceSettingsProbe(state: state)
                }
                .task { await state.run() }
        }
    }
}

private struct AppearanceSettingsProbe: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    let state: AppearanceRegressionState

    var body: some View {
        AppearanceProbe(state: state, isSheet: true)
            .overlay {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            .onAppear { state.pickerSelection = appearance }
            .onChange(of: appearance) { _, choice in state.pickerSelection = choice }
    }
}

private struct AppearanceProbe: View {
    @Environment(\.colorScheme) private var scheme
    let state: AppearanceRegressionState
    let isSheet: Bool

    var body: some View {
        Color.chineseRoomBackground.ignoresSafeArea()
            .background { AppearanceTraitProbe(state: state, isSheet: isSheet) }
            .onAppear { recordScheme(scheme) }
            .onChange(of: scheme) { _, value in recordScheme(value) }
    }

    private func recordScheme(_ value: ColorScheme) {
        if isSheet { state.sheetScheme = value }
        else { state.rootScheme = value }
    }
}

private struct AppearanceTraitProbe: UIViewRepresentable {
    let state: AppearanceRegressionState
    let isSheet: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if isSheet { state.sheetProbe = view }
        else { state.rootProbe = view }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor @Observable private final class AppearanceRegressionState {
    var showsSettings = false
    var rootScheme: ColorScheme?
    var sheetScheme: ColorScheme?
    var pickerSelection: AppAppearance?
    @ObservationIgnored weak var rootProbe: UIView?
    @ObservationIgnored weak var sheetProbe: UIView?
    private var hasRun = false

    func run() async {
        guard !hasRun else { return }
        hasRun = true
        await require("root window attached") { self.rootProbe?.window != nil }
        showsSettings = true
        await require("settings sheet attached") { self.sheetProbe?.window != nil }
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        await require("appearance launch override consumed") { arguments[AppAppearance.storageKey] == nil }
        if ProcessInfo.processInfo.arguments.contains("-appearanceRegressionSentinel") {
            await require("unrelated launch options preserved") {
                UserDefaults.standard.string(forKey: "appearanceRegressionSentinel") == "untouched"
            }
            await require("launch choice seeds Light before interactive changes") { self.matches(.light, includeSheet: true) }
        }
        for choice: AppAppearance in [.system, .light, .dark, .light, .system, .dark, .system, .light, .dark, .system] {
            UserDefaults.standard.set(choice.rawValue, forKey: AppAppearance.storageKey)
            await require("\(choice.rawValue) updates window, root, and open settings") {
                self.matches(choice, includeSheet: true)
            }
            print("PASS: \(choice.rawValue) updates SwiftUI and UIKit in the main view and open settings")
        }
        showsSettings = false
        await require("settings sheet dismissed") { self.sheetProbe?.window == nil }
        for choice: AppAppearance in [.light, .dark, .system] {
            UserDefaults.standard.set(choice.rawValue, forKey: AppAppearance.storageKey)
            await require("\(choice.rawValue) after closing settings") { self.matches(choice, includeSheet: false) }
        }
        print("PASS: appearance transitions, live sheet updates, palette colors, and System override reset")
        fflush(stdout)
        exit(0)
    }

    private func matches(_ choice: AppAppearance, includeSheet: Bool) -> Bool {
        guard let rootProbe, let window = rootProbe.window,
              window.overrideUserInterfaceStyle == choice.interfaceStyle else { return false }
        let expectedStyle = choice == .system
            ? (window.windowScene?.traitCollection.userInterfaceStyle ?? .light) : choice.interfaceStyle
        let expectedScheme: ColorScheme = expectedStyle == .dark ? .dark : .light
        guard rootScheme == expectedScheme, rootProbe.traitCollection.userInterfaceStyle == expectedStyle,
              paletteMatches(rootProbe.traitCollection, isDark: expectedScheme == .dark) else { return false }
        if includeSheet {
            guard let sheetProbe, pickerSelection == choice, sheetScheme == expectedScheme,
                  sheetProbe.traitCollection.userInterfaceStyle == expectedStyle,
                  paletteMatches(sheetProbe.traitCollection, isDark: expectedScheme == .dark) else { return false }
        }
        return true
    }

    private func paletteMatches(_ traits: UITraitCollection, isDark: Bool) -> Bool {
        let background = isDark ? [31.0 / 255, 24.0 / 255, 19.0 / 255] : [0.91, 0.86, 0.75]
        let ink = isDark ? [240.0 / 255, 226.0 / 255, 202.0 / 255] : [0.0, 0.0, 0.0]
        return matchesColor(.chineseRoomBackground, traits: traits, expected: background)
            && matchesColor(.chineseRoomInk, traits: traits, expected: ink)
    }

    private func matchesColor(_ color: UIColor, traits: UITraitCollection, expected: [Double]) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return zip([red, green, blue], expected).allSatisfy { abs(Double($0.0) - $0.1) < 0.0001 }
    }

    private func require(_ description: String, _ predicate: () -> Bool) async {
        for _ in 0..<300 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        print("FAIL: \(description); root=\(String(describing: rootScheme)), sheet=\(String(describing: sheetScheme)), override=\(String(describing: rootProbe?.window?.overrideUserInterfaceStyle))")
        fflush(stdout)
        exit(1)
    }
}
