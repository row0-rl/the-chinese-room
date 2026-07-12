import SwiftUI

struct MessageHomeView: View {
    let store: MessageStore
    let appStrings: AppStrings
    @State private var inputText = ""
    @State private var showsKeyboardInput = false
    @State private var showsLanguageSelector = false
    @State private var cardDragOffsetY: CGFloat = 0
    @State private var cardSettledOffsetY: CGFloat = 0
    @State private var isCompletingCardSwipe = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.chineseRoomBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                let cardViewportHeight = cardViewportHeight(in: proxy.size.height)

                VStack(spacing: 0) {
                    if let errorMessage = store.errorMessage {
                        ErrorBanner(message: errorMessage)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                    }

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
        }
        .foregroundStyle(.black)
        .animation(.snappy(duration: 0.2), value: store.nextRandomPreviewText)
        .onChange(of: store.currentMessage.id) { _, _ in
            Haptics.messageChanged()
        }
        .sheet(isPresented: $showsLanguageSelector) {
            LanguageSelectionView(
                languageMode: store.currentLanguageMode,
                appStrings: appStrings
            ) { languageMode in
                store.updateLanguageMode(languageMode)
            }
        }
    }

    private var floatingLocalIndicator: some View {
        HStack {
            if store.usesLocalMessages {
                Text("Local")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.08))
                    .clipShape(Capsule())
                    .accessibilityLabel("Using local sample messages")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }

    private func cardViewportHeight(in availableHeight: CGFloat) -> CGFloat {
        let inputReserve: CGFloat = showsKeyboardInput ? 118 : 96
        let dictatedReserve: CGFloat = store.isDictating || store.isTranscribing || !store.dictatedText.isEmpty ? 58 : 0
        let previewReserve: CGFloat = 0
        let reservedHeight = inputReserve + dictatedReserve + previewReserve + 8
        return max(520, availableHeight - reservedHeight)
    }

    private func cardStack(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewportHeight = proxy.size.height
            let peekHeight: CGFloat = 72
            let cardHeight = max(300, min(380, viewportHeight - 120))
            let currentCenterY = viewportHeight / 2
            let previousCenterY = -cardHeight / 2 + peekHeight
            let nextCenterY = viewportHeight + cardHeight / 2 - peekHeight
            let previousDistance = currentCenterY - previousCenterY
            let nextDistance = nextCenterY - currentCenterY
            let activeOffset = clampedCardOffset(
                cardDragOffsetY + cardSettledOffsetY,
                previousDistance: previousDistance,
                nextDistance: nextDistance
            )
            let previousProgress = min(1, max(0, activeOffset / previousDistance))
            let nextProgress = min(1, max(0, -activeOffset / nextDistance))

            ZStack {
                stackedCard(
                    message: store.previousCardMessage,
                    edge: .bottom,
                    progress: previousProgress
                )
                    .frame(width: proxy.size.width, height: cardHeight)
                    .position(x: proxy.size.width / 2, y: previousCenterY + activeOffset)

                currentCard
                    .frame(width: proxy.size.width, height: cardHeight)
                    .position(x: proxy.size.width / 2, y: currentCenterY + activeOffset)

                nextStackedCard(progress: nextProgress)
                    .frame(width: proxy.size.width, height: cardHeight)
                    .position(x: proxy.size.width / 2, y: nextCenterY + activeOffset)
            }
            .mask(cardStackFadeMask)
            .contentShape(Rectangle())
            .simultaneousGesture(
                cardSwipeGesture(
                    previousDistance: previousDistance,
                    nextDistance: nextDistance
                )
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var currentCard: some View {
        Group {
            if store.isShowingBlankCard {
                MessageSkeletonCard()
                    .id("blank-\(store.currentMessage.id)")
            } else {
                messageCard(store.currentMessage)
                    .id(store.currentMessage.id)
            }
        }
    }

    private func messageCard(_ message: LearningMessage) -> some View {
        MessageCard(message: message, examplesTitle: appStrings.examplesTitle) {
            Task { await store.speakCurrentMessage() }
        }
    }

    private func peekCard(message: LearningMessage?, edge: VerticalEdge) -> some View {
        Group {
            if let message {
                MessagePeekCard(message: message, edge: edge)
                    .opacity(0.72)
                    .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
    }

    private func stackedCard(message: LearningMessage?, edge: VerticalEdge, progress: CGFloat) -> some View {
        Group {
            if let message {
                ZStack {
                    MessagePeekCard(message: message, edge: edge)
                        .opacity(0.72 * Double(1 - progress))

                    messageCard(message)
                        .opacity(Double(progress))
                }
                .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
    }

    private func nextStackedCard(progress: CGFloat) -> some View {
        Group {
            if let message = store.nextCardMessage {
                stackedCard(message: message, edge: .top, progress: progress)
            } else if progress > 0.001 {
                MessageSkeletonCard()
                    .opacity(max(0.72, Double(progress)))
                    .allowsHitTesting(false)
            } else {
                Color.clear
            }
        }
    }

    private var cardStackFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42)

            Rectangle()
                .fill(.black)

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 42)
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
        .accessibilityLabel("Select languages: \(store.currentLanguageMode.displayName)")
    }

    private var inputArea: some View {
        VStack(spacing: 12) {
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
        Text(store.dictatedText.isEmpty ? "Listening..." : store.dictatedText)
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
            TextField("Type an expression", text: $inputText, axis: .vertical)
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
            .accessibilityLabel("Send expression")
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
                    .accessibilityLabel("Hold to speak")
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
            .accessibilityLabel("Type with keyboard")

            Spacer(minLength: 0)
        }
        .frame(height: 48)
    }

    private func cardSwipeGesture(previousDistance: CGFloat, nextDistance: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isCompletingCardSwipe else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                cardDragOffsetY = clampedCardOffset(
                    value.translation.height,
                    previousDistance: previousDistance,
                    nextDistance: nextDistance
                )
            }
            .onEnded { value in
                guard !isCompletingCardSwipe else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else {
                    resetCardDrag()
                    return
                }

                let threshold: CGFloat = 84
                let predictedThreshold: CGFloat = 132
                if cardDragOffsetY < -threshold || value.predictedEndTranslation.height < -predictedThreshold {
                    completeCardSwipe(.next, distance: nextDistance)
                } else if (cardDragOffsetY > threshold || value.predictedEndTranslation.height > predictedThreshold),
                          store.previousCardMessage != nil {
                    completeCardSwipe(.previous, distance: previousDistance)
                } else {
                    resetCardDrag()
                }
            }
    }

    private func clampedCardOffset(_ offset: CGFloat, previousDistance: CGFloat, nextDistance: CGFloat) -> CGFloat {
        let minimumOffset: CGFloat = -nextDistance
        let maximumOffset: CGFloat = store.previousCardMessage == nil ? 0 : previousDistance
        return min(max(offset, minimumOffset), maximumOffset)
    }

    private func completeCardSwipe(_ direction: CardSwipeDirection, distance: CGFloat) {
        isCompletingCardSwipe = true
        let targetOffset = direction == .next ? -distance : distance

        withAnimation(.snappy(duration: 0.28)) {
            cardSettledOffsetY = targetOffset
            cardDragOffsetY = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch direction {
                case .next:
                    if store.nextCardMessage == nil {
                        store.showBlankNextMessage()
                    } else {
                        store.commitNextVisibleMessage()
                    }
                case .previous:
                    store.commitPreviousVisibleMessage()
                }
                cardSettledOffsetY = 0
                cardDragOffsetY = 0
                isCompletingCardSwipe = false
            }

            if direction == .next, store.isShowingBlankCard {
                await store.finishBlankNextMessage()
            }
        }
    }

    private func resetCardDrag() {
        withAnimation(.snappy(duration: 0.2)) {
            cardDragOffsetY = 0
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

private enum CardSwipeDirection {
    case next
    case previous
}

private struct MessagePeekCard: View {
    let message: LearningMessage
    let edge: VerticalEdge

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if edge == .bottom {
                Spacer(minLength: 0)
            }

            Text(message.normalizedSourceText)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if edge == .top {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .topLeading : .bottomLeading)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MessageSkeletonCard: View {
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
        .frame(height: 360, alignment: .topLeading)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
        .accessibilityLabel(AppLocale.english.strings.loadingMessageLabel)
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(height / 2, 8))
            .fill(.black.opacity(0.12))
            .frame(width: width, height: height)
    }
}

private struct LanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    let appStrings: AppStrings
    let onSave: (LanguageMode) -> Void

    init(languageMode: LanguageMode, appStrings: AppStrings, onSave: @escaping (LanguageMode) -> Void) {
        _source = State(initialValue: languageMode.source)
        _target = State(initialValue: languageMode.target)
        self.appStrings = appStrings
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(appStrings.originalLanguageTitle) {
                    Picker(appStrings.originalLanguageTitle, selection: $source) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }
                }

                Section(appStrings.targetLanguageTitle) {
                    Picker(appStrings.targetLanguageTitle, selection: $target) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(language.displayName)
                                .tag(language)
                        }
                    }
                }
            }
            .navigationTitle(appStrings.languageSelectorTitle)
            .navigationBarTitleDisplayMode(.inline)
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
