import SwiftUI
import SwiftData

struct AppView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var store: MessageStore
    @State private var needsLanguageSetup: Bool
    private let appLocale = AppLocale.english

    init() {
        let savedMode = LanguageModeStorage.currentMode
        let initialMode = savedMode ?? .defaultMode
        _store = State(initialValue: MessageStore(configuration: .current, initialLanguageMode: initialMode))
        _needsLanguageSetup = State(initialValue: savedMode == nil)
    }

    var body: some View {
        Group {
            if needsLanguageSetup {
                FirstLaunchLanguageModeView(
                    initialMode: store.currentLanguageMode,
                    appStrings: appLocale.strings
                ) { selectedMode in
                    store.updateLanguageMode(selectedMode)
                    needsLanguageSetup = false
                }
            } else {
                MessageHomeView(store: store, appStrings: appLocale.strings)
            }
        }
        .onAppear {
            store.attachPersistence(modelContext)
        }
    }
}

#Preview {
    AppView()
}

private struct FirstLaunchLanguageModeView: View {
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    let appStrings: AppStrings
    let onContinue: (LanguageMode) -> Void

    init(initialMode: LanguageMode, appStrings: AppStrings, onContinue: @escaping (LanguageMode) -> Void) {
        _source = State(initialValue: initialMode.source)
        _target = State(initialValue: initialMode.target)
        self.appStrings = appStrings
        self.onContinue = onContinue
    }

    var body: some View {
        ZStack {
            Color.chineseRoomBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text(appStrings.firstLaunchTitle)
                        .font(.largeTitle.weight(.bold))
                    Text(appStrings.firstLaunchSubtitle)
                        .font(.body)
                        .foregroundStyle(.black.opacity(0.65))
                }

                VStack(spacing: 14) {
                    languagePicker(title: appStrings.originalLanguageTitle, selection: $source)
                    languagePicker(title: appStrings.targetLanguageTitle, selection: $target)
                }

                Button {
                    onContinue(LanguageMode(source: source, target: target))
                } label: {
                    Text(appStrings.continueButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(source == target ? .black.opacity(0.25) : .black)
                        .foregroundStyle(Color.chineseRoomBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(source == target)

                Spacer()
            }
            .padding(28)
        }
        .foregroundStyle(.black)
    }

    private func languagePicker(title: String, selection: Binding<LanguageProfile>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black.opacity(0.7))

            Picker(title, selection: selection) {
                ForEach(LanguageCatalog.supportedLanguages) { language in
                    Text("\(language.displayName) · \(language.nativeName)")
                        .tag(language)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
