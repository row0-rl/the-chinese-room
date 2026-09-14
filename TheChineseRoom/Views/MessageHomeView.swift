import SwiftUI

struct MessageHomeView: View {
    let store: MessageStore
    let appStrings: AppStrings
    @State private var inputText = ""
    @State private var showsKeyboardInput = false
    @State private var showsLanguageSelector = false
    @State private var showsSettings = false
    @State private var cardDragOffset: CGFloat = 0
    @State private var isPaging = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.chineseRoomBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                let cardViewportHeight = cardViewportHeight(in: proxy.size.height)

                VStack(spacing: 0) {
                    cardStack(height: cardViewportHeight)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 8)
                    inputArea
                }
            }

            if showsKeyboardInput {
                keyboardDismissLayer
            }

            floatingLocalIndicator
            settingsButton
        }
        .foregroundStyle(.black)
        .onChange(of: store.currentMessage.id) { _, _ in
            Haptics.messageChanged()
            recenterCardPager()
        }
        .onChange(of: store.isShowingBlankCard) { _, isShowingBlankCard in
            guard isShowingBlankCard else { return }
            recenterCardPager()
        }
        .sheet(isPresented: $showsLanguageSelector) {
            LanguageSelectionView(
                languageMode: store.currentLanguageMode
            ) { languageMode in
                store.updateLanguageMode(languageMode)
            }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(store: store)
        }
    }

    private var floatingLocalIndicator: some View {
        HStack {
            if store.usesLocalMessages {
                Text(appStrings.localTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.08))
                    .clipShape(Capsule())
                    .accessibilityLabel(appStrings.localLabel)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }

    private var settingsButton: some View {
        HStack {
            Spacer()
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.42))
                    .foregroundStyle(.black)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appStrings.settingsTitle)
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func cardViewportHeight(in availableHeight: CGFloat) -> CGFloat {
        let inputReserve: CGFloat = showsKeyboardInput ? 118 : 96
        let dictatedReserve: CGFloat = store.isDictating || store.isTranscribing || !store.dictatedText.isEmpty ? 58 : 0
        let previewReserve: CGFloat = 0
        let errorReserve: CGFloat = store.generationError == nil ? 0 : 92
        let reservedHeight = inputReserve + dictatedReserve + previewReserve + errorReserve + 8
        return max(520, availableHeight - reservedHeight)
    }

    private func cardStack(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewportHeight = proxy.size.height
            let peekHeight: CGFloat = 64
            let cardHeight = max(300, min(380, viewportHeight - 120))
            // A centered card leaves exactly peekHeight of each neighbor visible.
            let pageStride = (viewportHeight + cardHeight) / 2 - peekHeight

            ZStack {
                if let previousMessage = store.previousCardMessage {
                    MessageTitlePreview(title: previousMessage.normalizedSourceText, loadingLabel: appStrings.loadingMessageLabel, edge: .bottom)
                        .frame(width: proxy.size.width, height: cardHeight)
                        .offset(y: -pageStride + cardDragOffset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                currentCard
                    .frame(width: proxy.size.width, height: cardHeight)
                    .offset(y: cardDragOffset)
                    .allowsHitTesting(!isPaging)

                nextCard
                    .frame(width: proxy.size.width, height: cardHeight)
                    .offset(y: pageStride + cardDragOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: proxy.size.width, height: viewportHeight)
            .contentShape(Rectangle())
            .clipped()
            .mask(cardStackFadeMask)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !isPaging else { return }
                        let translation = value.translation.height
                        // Resist dragging beyond the available history.
                        if translation > 0, store.previousCardMessage == nil {
                            cardDragOffset = min(40, translation * 0.15)
                        } else {
                            cardDragOffset = min(pageStride, max(-pageStride, translation))
                        }
                    }
                    .onEnded { value in
                        guard !isPaging else { return }
                        let projectedOffset = value.predictedEndTranslation.height
                        let page: CardPagerPage
                        if projectedOffset < -pageStride * 0.3 {
                            page = .next
                        } else if projectedOffset > pageStride * 0.3, store.previousCardMessage != nil {
                            page = .previous
                        } else {
                            page = .current
                        }
                        settleCardPager(on: page, stride: pageStride)
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var currentCard: some View {
        Group {
            if store.isShowingBlankCard {
                MessageSkeletonCard(loadingLabel: appStrings.loadingMessageLabel)
                    .id("blank-\(store.currentMessage.id)")
            } else {
                messageCard(store.currentMessage)
                    .id(store.currentMessage.id)
            }
        }
    }

    private func messageCard(_ message: LearningMessage) -> some View {
        MessageCard(message: message, appStrings: appStrings) {
            Task { await store.speakCurrentMessage() }
        }
    }

    private var nextCard: some View {
        MessageTitlePreview(title: store.nextCardMessage?.normalizedSourceText, loadingLabel: store.isPreparingNextRandom || store.isGenerating ? appStrings.loadingMessageLabel : appStrings.nextMessageLabel, edge: .top)
    }

    private var cardStackFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            Rectangle()
                .fill(.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
        }
    }

    private var languageSelectorButton: some View {
        Button {
            showsLanguageSelector = true
        } label: {
            Image(systemName: "translate")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
            .background(.white.opacity(0.42))
                .foregroundStyle(.black)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(appStrings.languageSelectorTitle): \(appStrings.languageName(store.currentLanguageMode.source)) → \(appStrings.languageName(store.currentLanguageMode.target))")
    }

    private var inputArea: some View {
        VStack(spacing: 12) {
            if let error = store.generationError {
                ErrorBanner(message: error)
            }
            if showsKeyboardInput {
                typedInputBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                if store.isDictating || store.isTranscribing || !store.dictatedText.isEmpty {
                    dictatedTextPreview
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                inputBar
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .animation(.snappy(duration: 0.2), value: showsKeyboardInput)
        .animation(.snappy(duration: 0.2), value: store.dictatedText)
    }

    private var keyboardDismissLayer: some View {
        VStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboardMode()
                }

            Color.clear
                .frame(height: 84)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var dictatedTextPreview: some View {
        Text(store.dictatedText.isEmpty ? appStrings.listeningLabel : store.dictatedText)
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(.black.opacity(store.dictatedText.isEmpty ? 0.55 : 0.85))
            .lineLimit(3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.white.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var typedInputBar: some View {
        HStack(spacing: 10) {
            TextField(appStrings.inputPlaceholder, text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.black)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isGenerating)
            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
            .accessibilityLabel(appStrings.sendLabel)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            languageSelectorButton

            Image(systemName: store.isDictating ? "stop.fill" : "mic.fill")
                .font(.title2)
                .frame(maxWidth: 260)
                .frame(height: 48)
                .background(store.isDictating ? .red : .black)
                .foregroundStyle(Color.chineseRoomBackground)
                .clipShape(Capsule())
                .contentShape(Capsule())
                    .accessibilityLabel(appStrings.holdToSpeakLabel)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !store.isDictating else { return }
                        Haptics.dictationStarted()
                        Task { await store.startDictation() }
                    }
                    .onEnded { _ in
                        Task { await store.finishDictationAndSubmit() }
                    }
            )

            Button {
                showsKeyboardInput.toggle()
                isInputFocused = showsKeyboardInput
            } label: {
                Image(systemName: "keyboard")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.58))
                    .foregroundStyle(.black)
                    .clipShape(Circle())
            }
            .accessibilityLabel(appStrings.keyboardLabel)

            Spacer(minLength: 0)
        }
        .frame(height: 48)
    }

    private func commitSettledCardPage(_ page: CardPagerPage) {
        guard page != .current else { return }

        var shouldGenerateNextMessage = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch page {
            case .previous:
                store.commitPreviousVisibleMessage()
            case .current:
                break
            case .next:
                if store.nextCardMessage == nil {
                    store.showBlankNextMessage()
                    shouldGenerateNextMessage = store.isShowingBlankCard
                } else {
                    store.commitNextVisibleMessage()
                }
            }
        }

        if shouldGenerateNextMessage {
            Task { await store.finishBlankNextMessage() }
        }
    }

    private func settleCardPager(on page: CardPagerPage, stride: CGFloat) {
        let sourceMessageID = store.currentMessage.id
        isPaging = true
        withAnimation(.snappy(duration: 0.28), completionCriteria: .removed) {
            switch page {
            case .previous: cardDragOffset = stride
            case .current: cardDragOffset = 0
            case .next: cardDragOffset = -stride
            }
        } completion: {
            // Reveal full content only after the title preview reaches the center.
            // Swap atomically so preview and full titles never overlap.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if store.currentMessage.id == sourceMessageID {
                    commitSettledCardPage(page)
                }
                cardDragOffset = 0
                isPaging = false
            }
        }
    }

    private func recenterCardPager() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            cardDragOffset = 0
        }
    }

    private func submitInput() {
        let submittedText = inputText
        inputText = ""
        dismissKeyboardMode()
        Task { await store.submit(submittedText) }
    }

    private func dismissKeyboardMode() {
        showsKeyboardInput = false
        isInputFocused = false
    }
}

private enum CardPagerPage: Hashable {
    case previous
    case current
    case next
}

/// Neighbors contain only one title, anchored inside the visible 64-point edge.
/// Full message content is introduced when paging commits, without a crossfade.
private struct MessageTitlePreview: View {
    let title: String?
    let loadingLabel: String
    let edge: VerticalEdge

    var body: some View {
        Text(title ?? loadingLabel)
            .font(.title3.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.black.opacity(title == nil ? 0.45 : 1))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity,
                   alignment: edge == .top ? .topLeading : .bottomLeading)
            .background(.white.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct MessageSkeletonCard: View {
    let loadingLabel: String
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    skeletonBar(width: 210, height: 28)
                    skeletonBar(width: 140, height: 16)
                }

                Spacer()

                Circle()
                    .fill(.black.opacity(0.08))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 12) {
                skeletonBar(width: 260, height: 58)
                skeletonBar(width: 180, height: 58)
                skeletonBar(width: 230, height: 22)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
        .accessibilityLabel(loadingLabel)
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(height / 2, 8))
            .fill(.black.opacity(0.12))
            .frame(width: width, height: height)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    @State private var selectedVoiceIdentifier: String?
    let store: MessageStore
    private var appStrings: AppStrings { AppLocale.forLanguage(source).strings }

    init(store: MessageStore) {
        self.store = store
        _source = State(initialValue: store.currentLanguageMode.source)
        _target = State(initialValue: store.currentLanguageMode.target)
        _selectedVoiceIdentifier = State(
            initialValue: store.selectedVoiceIdentifier(for: store.currentLanguageMode)
        )
    }

    private var editedMode: LanguageMode {
        LanguageMode(source: source, target: target)
    }

    private var voices: [SpeechVoice] {
        store.availableVoices(for: editedMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appStrings.learningModeTitle) {
                    Picker(appStrings.originalLanguageTitle, selection: $source) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language)).tag(language)
                        }
                    }

                    Picker(appStrings.targetLanguageTitle, selection: $target) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language)).tag(language)
                        }
                    }
                }

                Section {
                    Picker(appStrings.voiceTitle, selection: $selectedVoiceIdentifier) {
                        Text(appStrings.systemDefaultTitle).tag(String?.none)
                        ForEach(voices) { voice in
                            Text("\(voice.name) · \(voice.qualityDescription == "Enhanced" ? appStrings.enhancedVoiceTitle : appStrings.defaultVoiceTitle)")
                                .tag(Optional(voice.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("\(appStrings.languageName(target)) · \(appStrings.voiceTitle)")
                } footer: {
                    Text(appStrings.voiceFooter)
                }
            }
            .navigationTitle(appStrings.settingsTitle)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.locale, Locale(identifier: appStrings.localeIdentifier))
            .onChange(of: source) { oldValue, _ in
                guard oldValue != source else { return }
                loadVoiceForEditedMode()
            }
            .onChange(of: target) { oldValue, _ in
                guard oldValue != target else { return }
                loadVoiceForEditedMode()
            }
            .onChange(of: selectedVoiceIdentifier) { oldValue, newValue in
                guard oldValue != newValue else { return }
                Task {
                    await store.previewVoice(newValue, for: editedMode)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appStrings.cancelButtonTitle) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appStrings.doneButtonTitle) {
                        store.updateVoiceIdentifier(selectedVoiceIdentifier, for: editedMode)
                        store.updateLanguageMode(editedMode)
                        dismiss()
                    }
                    .disabled(source == target)
                }
            }
        }
    }

    private func loadVoiceForEditedMode() {
        selectedVoiceIdentifier = store.selectedVoiceIdentifier(for: editedMode)
    }
}

private struct LanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    private var appStrings: AppStrings { AppLocale.forLanguage(source).strings }
    let onSave: (LanguageMode) -> Void

    init(languageMode: LanguageMode, onSave: @escaping (LanguageMode) -> Void) {
        _source = State(initialValue: languageMode.source)
        _target = State(initialValue: languageMode.target)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appStrings.originalLanguageTitle) {
                    Picker(appStrings.originalLanguageTitle, selection: $source) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language))
                                .tag(language)
                        }
                    }
                }

                Section(appStrings.targetLanguageTitle) {
                    Picker(appStrings.targetLanguageTitle, selection: $target) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language))
                                .tag(language)
                        }
                    }
                }
            }
            .navigationTitle(appStrings.languageSelectorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.locale, Locale(identifier: appStrings.localeIdentifier))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appStrings.cancelButtonTitle) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appStrings.doneButtonTitle) {
                        onSave(LanguageMode(source: source, target: target))
                        dismiss()
                    }
                    .disabled(source == target)
                }
            }
        }
    }
}
