import SwiftUI
import UIKit

struct MessageHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dictationStartTask: Task<Void, Never>?
    let store: MessageStore
    let appStrings: AppStrings
    @State private var inputText = ""
    @State private var showsKeyboardInput = false
    @State private var showsLanguageSelector = false
    @State private var showsSettings = false
    @State private var cardDragOffset: CGFloat = 0
    @State private var isPaging = false
    @State private var cardDragHaptics = CardDragHaptics()
    @State private var skipNextCardImpact = false
    @GestureState private var isDraggingCard = false
    @State private var cardHeights: [UUID: CGFloat] = [:]
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color.chineseRoomBackground
                .ignoresSafeArea()

            GeometryReader { proxy in
                let cardViewportHeight = cardViewportHeight(in: proxy.size.height)

                VStack(spacing: 0) {
                    Group {
                        if let pending = store.pendingDictationText {
                            pendingDictationCard(text: pending, height: cardViewportHeight)
                        } else {
                            cardStack(height: cardViewportHeight)
                        }
                    }
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
        .foregroundStyle(Color.chineseRoomInk)
        .onAppear { cardDragHaptics.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cardDragHaptics.stopRumble() }
            if phase == .background { cancelHeldDictation() }
        }
        .onDisappear {
            cardDragHaptics.stopRumble()
            cancelHeldDictation()
        }
        .onChange(of: isDraggingCard) { _, dragging in
            if !dragging && !isPaging { cardDragHaptics.stopRumble() }
        }
        .onChange(of: showsKeyboardInput || showsLanguageSelector || showsSettings) { _, presented in
            if presented { cardDragHaptics.stopRumble() }
        }
        .onChange(of: store.generationError) { _, error in
            if error != nil { skipNextCardImpact = false }
        }
        .onChange(of: store.currentMessage.id) { _, _ in
            cardDragHaptics.stopRumble()
            if skipNextCardImpact { skipNextCardImpact = false }
            else { Haptics.messageChanged() }
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
                    .appFont(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.chineseRoomInk.opacity(0.08))
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
                    .background(Color.chineseRoomControl(0.42))
                    .foregroundStyle(Color.chineseRoomInk)
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
        let previewReserve: CGFloat = 0
        let errorReserve: CGFloat = store.generationError == nil ? 0 : 92
        let reservedHeight = inputReserve + previewReserve + errorReserve + 8
        return max(0, availableHeight - reservedHeight)
    }

    private func pendingDictationCard(text: String, height: CGFloat) -> some View {
        let seed = store.pendingDictationID
        return ZStack(alignment: .top) {
            MessageTitlePreview(title: store.currentMessage.normalizedSourceText,
                loadingLabel: appStrings.loadingMessageLabel, edge: .bottom)
                .frame(height: 56)
            CappedCardScroll(maximumHeight: maximumCardHeight(in: height)) {
                VStack(alignment: .leading, spacing: 22) {
                    if text.isEmpty {
                        WritingWave()
                            .frame(width: 180, height: 24)
                    } else {
                        InkText(MessagePunctuation.clean(text))
                            .appFont(.title3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    WritingWave()
                        .frame(height: 64)
                        .accessibilityLabel(appStrings.loadingMessageLabel)
                }
                .padding(PencilRectangle.contentInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background { NotebookRules(seed: seed) }
            .background(Color.chineseRoomCard, in: PencilRectangleShape(seed: seed))
            .clipShape(PencilRectangleShape(seed: seed))
            .overlay(PencilRectangle(seed: seed))
            .frame(height: height, alignment: .center)
        }
        .frame(height: height)
        .clipped()
    }

    private func cardStack(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewportHeight = proxy.size.height
            let previousStride = abs(cardPosition(-1, viewportHeight: viewportHeight))
            let nextStride = cardPosition(1, viewportHeight: viewportHeight)
            let destination = cardDragOffset > 0 ? -1 : 1
            let progress = min(1, abs(cardDragOffset) / max(1, destination == -1 ? previousStride : nextStride))

            ZStack {
                ForEach(visibleCards, id: \.message.id) { card in
                    let restingOffset = cardPosition(card.position, viewportHeight: viewportHeight)
                    let destinationOffset = cardPosition(card.position, centeredAt: destination, viewportHeight: viewportHeight)
                    let offset = restingOffset + (destinationOffset - restingOffset) * progress
                    messageCard(
                        card.message,
                        revealProgress: card.position == 0 ? 1 - progress : (card.position == destination ? progress : 0),
                        previewEdge: offset < 0 ? .bottom : .top,
                        maximumHeight: maximumCardHeight(in: viewportHeight)
                    )
                    .frame(width: proxy.size.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        cardHeights[card.message.id] = height
                    }
                    .offset(y: offset)
                    .allowsHitTesting(card.position == 0 && !isPaging)
                    .accessibilityHidden(card.position != 0)
                }

                if store.isShowingBlankCard {
                    MessageSkeletonCard(loadingLabel: appStrings.loadingMessageLabel)
                        .frame(width: proxy.size.width, height: 120)
                        .offset(y: cardDragOffset)
                }

                ForEach(1...2, id: \.self) { position in
                    if store.cardMessage(at: position) == nil {
                        nextCard
                            .frame(width: proxy.size.width, height: 120)
                            .offset(y: cardPosition(position, viewportHeight: viewportHeight) * (1 - progress)
                                + cardPosition(position, centeredAt: destination, viewportHeight: viewportHeight) * progress)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: proxy.size.width, height: viewportHeight)
            .contentShape(Rectangle())
            .clipped()
            .mask(cardStackFadeMask)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($isDraggingCard) { value, dragging, _ in
                        if !isPaging && !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) {
                            dragging = true
                        }
                    }
                    .onChanged { value in
                        guard !isPaging, !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) else { return }
                        let translation = value.translation.height
                        // Resist dragging beyond the available history.
                        if translation > 0, store.previousCardMessage == nil {
                            cardDragOffset = min(40, translation * 0.15)
                        } else {
                            cardDragOffset = min(previousStride, max(-nextStride, translation))
                        }
                        if cardDragOffset != 0 { cardDragHaptics.beginRumble() }
                    }
                    .onEnded { value in
                        guard !isPaging, !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) else { return }
                        cardDragHaptics.stopRumble()
                        Haptics.messageChanged()
                        let projectedOffset = value.predictedEndTranslation.height
                        let page: CardPagerPage
                        if projectedOffset < -nextStride * 0.3 {
                            page = .next
                        } else if projectedOffset > previousStride * 0.3, store.previousCardMessage != nil {
                            page = .previous
                        } else {
                            page = .current
                        }
                        settleCardPager(on: page, stride: page == .previous ? previousStride : nextStride)
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private func maximumCardHeight(in viewportHeight: CGFloat) -> CGFloat {
        min(520, max(1, viewportHeight - 136))
    }

    private func scrollsInsideCard(_ location: CGPoint, viewportHeight: CGFloat) -> Bool {
        let height = cardHeight(at: 0)
        let capped = height >= maximumCardHeight(in: viewportHeight) - 1
        return capped && abs(location.y - viewportHeight / 2) <= height / 2
    }

    private func cardPosition(_ position: Int, centeredAt center: Int = 0, viewportHeight: CGFloat) -> CGFloat {
        let relativePosition = position - center
        guard relativePosition != 0 else { return 0 }
        let direction = relativePosition > 0 ? 1 : -1
        let firstNeighbor = center + direction
        // Keep exactly 56 points of each adjacent preview inside the viewport,
        // independent of the active card's content height.
        var distance = viewportHeight / 2 + cardHeight(at: firstNeighbor) / 2 - 56
        if abs(relativePosition) > 1 {
            for step in 1..<abs(relativePosition) {
                distance += cardHeight(at: center + step * direction) / 2
                    + 12 + cardHeight(at: center + (step + 1) * direction) / 2
            }
        }
        return CGFloat(direction) * distance
    }

    private func cardHeight(at position: Int) -> CGFloat {
        guard let message = store.cardMessage(at: position) else { return 120 }
        return cardHeights[message.id] ?? 180
    }

    private var visibleCards: [(message: LearningMessage, position: Int)] {
        (-2...2).compactMap { position in
            guard !(position == 0 && store.isShowingBlankCard),
                  let message = store.cardMessage(at: position) else { return nil }
            return (message, position)
        }
    }

    private func messageCard(
        _ message: LearningMessage,
        revealProgress: CGFloat,
        previewEdge: VerticalEdge,
        maximumHeight: CGFloat
    ) -> some View {
        MessageCard(
            message: message,
            appStrings: appStrings,
            notationSystem: .fixedSystem(for: store.currentLanguageMode.target),
            isLoadingPronunciation: store.isLoadingPronunciation(for: message.id),
            pronunciationFailed: store.pronunciationFailed(for: message.id),
            isLoadingHanja: store.isLoadingHanja(for: message.id),
            hanjaFailed: store.hanjaFailed(for: message.id),
            onRequestAnnotations: {
                store.ensurePronunciation(for: message.id)
                store.ensureHanja(for: message.id)
            },
            onSpeak: {
            Task { await store.speakCurrentMessage() }
            },
            maximumHeight: maximumHeight,
            isCurrentCard: message.id == store.currentMessage.id && !store.isShowingBlankCard,
            revealProgress: revealProgress,
            previewEdge: previewEdge
        )
    }

    private var nextCard: some View {
        MessageTitlePreview(title: nil, loadingLabel: store.isPreparingNextRandom || store.isGenerating ? appStrings.loadingMessageLabel : appStrings.nextMessageLabel, edge: .top)
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
            .background(Color.chineseRoomControl(0.42))
                .foregroundStyle(Color.chineseRoomInk)
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
                inputBar
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .animation(.snappy(duration: 0.2), value: showsKeyboardInput)
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

    private var typedInputBar: some View {
        HStack(spacing: 10) {
            TextField(appStrings.inputPlaceholder, text: $inputText, axis: .vertical)
                .appFont(.body)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.chineseRoomControl(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                submitInput()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.chineseRoomInk)
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

            DictationPressButton(
                label: appStrings.holdToSpeakLabel,
                enabled: !store.isGenerating && !store.isTranscribing,
                foreground: .chineseRoomBackground,
                onPress: {
                    cardDragHaptics.stopRumble()
                    skipNextCardImpact = false
                    dictationStartTask = Task {
                        guard !Task.isCancelled else { return }
                        await store.startDictation()
                    }
                },
                onRelease: { cancelled in
                    if cancelled || store.isStartingDictation || !store.isDictating {
                        dictationStartTask?.cancel()
                        store.cancelDictation()
                    } else {
                        Task { await store.finishDictationAndSubmit() }
                    }
                    dictationStartTask = nil
                }
            )
            .frame(maxWidth: 260)
            .frame(height: 48)

            Button {
                showsKeyboardInput.toggle()
                isInputFocused = showsKeyboardInput
            } label: {
                Image(systemName: "keyboard")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.chineseRoomControl(0.58))
                    .foregroundStyle(Color.chineseRoomInk)
                    .clipShape(Circle())
            }
            .accessibilityLabel(appStrings.keyboardLabel)

            Spacer(minLength: 0)
        }
        .frame(height: 48)
    }

    private func cancelHeldDictation() {
        dictationStartTask?.cancel()
        dictationStartTask = nil
        store.cancelDictation()
    }

    private func commitSettledCardPage(_ page: CardPagerPage) -> Bool {
        guard page != .current else { return false }
        let previousID = store.currentMessage.id
        let wasBlank = store.isShowingBlankCard

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
        return store.currentMessage.id != previousID || (!wasBlank && store.isShowingBlankCard)
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
            cardDragHaptics.stopRumble()
            // Rebase positions after the continuous reveal reaches its destination.
            // Stable message IDs retain card state across this atomic rebase.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if store.currentMessage.id == sourceMessageID, scenePhase == .active {
                    if commitSettledCardPage(page) {
                        // The drag already fired its impact on finger release.
                        // Suppress the arriving card's notification to avoid a second impact.
                        skipNextCardImpact = true
                    }
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
        cardDragHaptics.stopRumble()
        skipNextCardImpact = false
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
        Group {
            if let title {
                Text(title)
                    .appFont(.title3)
                    .lineLimit(1)
                    .foregroundStyle(Color.chineseRoomInk)
            } else {
                WritingWave()
                    .frame(height: 24)
                    .accessibilityLabel(loadingLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PencilRectangle.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: edge == .top ? .topLeading : .bottomLeading)
        .background { NotebookRules(seed: PencilRectangle.placeholderSeed) }
        .background(Color.chineseRoomCard, in: PencilRectangleShape(seed: PencilRectangle.placeholderSeed))
        .clipShape(PencilRectangleShape(seed: PencilRectangle.placeholderSeed))
        .overlay(
            PencilRectangle(seed: PencilRectangle.placeholderSeed)
        )
    }
}

private struct MessageSkeletonCard: View {
    let loadingLabel: String
    var body: some View {
        WritingWave()
            .frame(height: 32)
            .padding(PencilRectangle.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .center)
            .background { NotebookRules(seed: PencilRectangle.placeholderSeed) }
            .background(Color.chineseRoomCard, in: PencilRectangleShape(seed: PencilRectangle.placeholderSeed))
            .clipShape(PencilRectangleShape(seed: PencilRectangle.placeholderSeed))
            .overlay(
                PencilRectangle(seed: PencilRectangle.placeholderSeed)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(loadingLabel)
    }
}

/// Repeatedly writes a pen-like wave from the left; it fades before starting over.
private struct WritingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    @State private var seed = UInt64.random(in: .min ... .max)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || scenePhase != .active)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(startedAt))
            let phase = elapsed.truncatingRemainder(dividingBy: 2)
            let progress = reduceMotion ? 1 : min(1, phase / 1.25)
            let opacity = reduceMotion || phase < 1.6 ? 1 : max(0, 1 - (phase - 1.6) / 0.2)
            WritingWaveShape(seed: seed &+ (reduceMotion ? 0 : UInt64(elapsed / 2)))
                .trim(from: 0, to: progress)
                .stroke(Color.chineseRoomInk, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .opacity(opacity * 0.5)
                .padding(.horizontal, 2)
        }
        .onAppear { startedAt = .now }
        .allowsHitTesting(false)
    }
}

private struct WritingWaveShape: Shape {
    let seed: UInt64

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let amplitude = min(9, rect.height * 0.3)
        var random = WritingWaveRandom(state: seed)
        var path = Path()
        var point = CGPoint(x: rect.minX, y: rect.midY)
        var direction: CGFloat = random.unit() < 0.5 ? -1 : 1
        path.move(to: point)
        while point.x < rect.maxX {
            let next = CGPoint(
                x: min(rect.maxX, point.x + 16 + random.unit() * 16),
                y: rect.midY + direction * amplitude * (0.45 + random.unit() * 0.55)
            )
            let controlX = (point.x + next.x) / 2
            path.addCurve(to: next,
                          control1: CGPoint(x: controlX, y: point.y),
                          control2: CGPoint(x: controlX, y: next.y))
            point = next
            direction *= -1
        }
        return path
    }
}

private struct WritingWaveRandom {
    var state: UInt64

    mutating func unit() -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        value ^= value >> 31
        return CGFloat(value >> 11) / CGFloat(UInt64(1) << 53)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: LanguageProfile
    @State private var target: LanguageProfile
    @State private var voicePreviewError: String?
    @State private var voicePreviewTask: Task<Void, Never>?
    @State private var isPreparingVoicePreview = false
    @State private var selectedVoiceIdentifier: String?
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    let store: MessageStore
    private var appStrings: AppStrings { AppLocale.forLanguage(source).strings }

    init(store: MessageStore) {
        self.store = store
        _source = State(initialValue: store.currentLanguageMode.source)
        _target = State(initialValue: store.currentLanguageMode.target)
        _selectedVoiceIdentifier = State(
            initialValue: store.availableVoices(for: store.currentLanguageMode)
                .first { $0.id == store.selectedVoiceIdentifier(for: store.currentLanguageMode) }?.id
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
                Section {
                    Picker(appStrings.originalLanguageTitle, selection: $source) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language)).appFont(.body).tag(language)
                        }
                    }
                    .appFont(.body)

                    Picker(appStrings.targetLanguageTitle, selection: $target) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language)).appFont(.body).tag(language)
                        }
                    }
                    .appFont(.body)
                } header: {
                    Text(appStrings.learningModeTitle).appFont(.footnote)
                }

                Section {
                    LabeledContent {
                        Text(appStrings.notationName(.fixedSystem(for: target)))
                            .appFont(.body)
                    } label: {
                        Text(appStrings.notationSystemTitle).appFont(.body)
                    }
                } header: {
                    Text("\(appStrings.languageName(target)) · \(appStrings.pronunciationTitle)")
                        .appFont(.footnote)
                } footer: {
                    Text(PronunciationNotationSystem.fixedSystem(for: target) == .pinyin
                        ? appStrings.pinyinFooter : appStrings.pronunciationFooter)
                        .appFont(.footnote)
                }

                Section {
                    if voices.isEmpty {
                        Text(appStrings.speechUnavailableTitle)
                            .appFont(.body)
                    } else {
                        Picker(appStrings.voiceTitle, selection: $selectedVoiceIdentifier) {
                            Text(appStrings.systemDefaultTitle).appFont(.body).tag(String?.none)
                            ForEach(voices) { voice in
                                Text("\(voice.name) · \(voice.qualityDescription)")
                                    .appFont(.body)
                                    .tag(Optional(voice.id))
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .appFont(.body)
                    }
                } header: {
                    Text("\(appStrings.languageName(target)) · \(appStrings.voiceTitle)")
                        .appFont(.footnote)
                } footer: {
                    Text(appStrings.voiceFooter)
                        .appFont(.footnote)
                    if isPreparingVoicePreview { ProgressView() }
                    if let voicePreviewError {
                        Text(voicePreviewError).appFont(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Picker(appStrings.appearanceTitle, selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(appStrings.appearanceName(option)).appFont(.body).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(appStrings.appearanceTitle).appFont(.footnote)
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
                voicePreviewTask?.cancel()
                voicePreviewError = nil
                isPreparingVoicePreview = true
                let mode = editedMode
                voicePreviewTask = Task {
                    defer { if !Task.isCancelled { isPreparingVoicePreview = false } }
                    do {
                        try await store.previewVoice(newValue, for: mode)
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        voicePreviewError = error.localizedDescription
                    }
                }
            }
            .onDisappear {
                voicePreviewTask?.cancel()
                isPreparingVoicePreview = false
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(appStrings.cancelButtonTitle) {
                        dismiss()
                    }
                    .appFont(.body)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appStrings.doneButtonTitle) {
                        store.updateVoiceIdentifier(selectedVoiceIdentifier, for: editedMode)
                        store.updateLanguageMode(editedMode)
                        dismiss()
                    }
                    .disabled(source == target)
                    .appFont(.body)
                }
            }
        }
    }

    private func loadVoiceForEditedMode() {
        selectedVoiceIdentifier = voices.first { $0.id == store.selectedVoiceIdentifier(for: editedMode) }?.id
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
                Section {
                    Picker(appStrings.originalLanguageTitle, selection: $source) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language))
                                .appFont(.body)
                                .tag(language)
                        }
                    }
                    .appFont(.body)
                } header: {
                    Text(appStrings.originalLanguageTitle).appFont(.footnote)
                }

                Section {
                    Picker(appStrings.targetLanguageTitle, selection: $target) {
                        ForEach(LanguageCatalog.supportedLanguages) { language in
                            Text(appStrings.languageName(language))
                                .appFont(.body)
                                .tag(language)
                        }
                    }
                    .appFont(.body)
                } header: {
                    Text(appStrings.targetLanguageTitle).appFont(.footnote)
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
                    .appFont(.body)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(appStrings.doneButtonTitle) {
                        onSave(LanguageMode(source: source, target: target))
                        dismiss()
                    }
                    .disabled(source == target)
                    .appFont(.body)
                }
            }
        }
    }
}

/// Native touch tracking keeps press feedback independent of SwiftUI card layout
/// and avoids using a drag recognizer to implement a stationary hold.
private struct DictationPressButton: UIViewRepresentable {
    @Environment(\.fontResolutionContext) private var fontContext
    let label: String
    let enabled: Bool
    let foreground: UIColor
    let onPress: () -> Void
    let onRelease: (Bool) -> Void

    func makeUIView(context: Context) -> DictationPressControl {
        DictationPressControl()
    }

    func updateUIView(_ control: DictationPressControl, context: Context) {
        control.accessibilityLabel = label
        control.tintColor = foreground
        control.setTitle(label, font: AppFont.withEastAsianFallback(
            AppFont.text(.title3).resolve(in: fontContext).ctFont
        ) as UIFont)
        control.onPress = onPress
        control.onRelease = onRelease
        control.isEnabled = enabled
        if !enabled { control.release(cancelled: true) }
    }

    static func dismantleUIView(_ control: DictationPressControl, coordinator: ()) {
        control.release(cancelled: true)
    }
}

private final class DictationPressControl: UIControl {
    var onPress: (() -> Void)?
    var onRelease: ((Bool) -> Void)?
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let microphoneImage = UIImage(named: "FuzzyMicrophone")?.withRenderingMode(.alwaysTemplate)
    private let feedback = UIImpactFeedbackGenerator(style: .heavy)
    private var held = false
    private var pressID = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isMultipleTouchEnabled = false
        backgroundColor = .chineseRoomInk
        icon.image = microphoneImage
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.isUserInteractionEnabled = false
        titleLabel.isAccessibilityElement = false
        addSubview(titleLabel)
        addSubview(icon)
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String, font: UIFont) {
        titleLabel.text = title
        titleLabel.font = font
        titleLabel.textColor = tintColor
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: ceil(titleLabel.intrinsicContentSize.width) + 68, height: 48)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let iconSize = min(28, max(0, bounds.height - 16))
        let gap: CGFloat = 8
        let titleWidth = min(ceil(titleLabel.intrinsicContentSize.width), max(0, bounds.width - 32 - gap - iconSize))
        let startX = (bounds.width - titleWidth - gap - iconSize) / 2
        titleLabel.frame = CGRect(x: startX, y: 0, width: titleWidth, height: bounds.height)
        icon.frame = CGRect(x: startX + titleWidth + gap, y: (bounds.height - iconSize) / 2,
                            width: iconSize, height: iconSize)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        #if DEBUG
        print("[Dictation touch] delivery=\(ProcessInfo.processInfo.systemUptime - touch.timestamp)s main=\(Thread.isMainThread)")
        #endif
        press()
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if !bounds.insetBy(dx: -20, dy: -20).contains(touch.location(in: self)) {
            release(cancelled: true)
            return false
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        release(cancelled: false)
    }

    override func cancelTracking(with event: UIEvent?) {
        release(cancelled: true)
    }

    private func press() {
        guard !held else { return }
        held = true
        let id = UUID()
        pressID = id
        // Update the native layer before scheduling any application work.
        UIView.performWithoutAnimation {
            backgroundColor = .systemRed
            icon.image = UIImage(systemName: "stop.fill")
        }
        #if DEBUG
        let changedAt = ProcessInfo.processInfo.systemUptime
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self, self.held, self.pressID == id else { return }
            #if DEBUG
            print("[Dictation touch] native color set; start dispatch=\(ProcessInfo.processInfo.systemUptime - changedAt)s")
            #endif
            self.onPress?()
            self.feedback.impactOccurred()
        }
    }

    func release(cancelled: Bool) {
        guard held else { return }
        held = false
        pressID = UUID()
        UIView.performWithoutAnimation {
            backgroundColor = .chineseRoomInk
            icon.image = microphoneImage
        }
        onRelease?(cancelled)
    }

    @objc private func backgrounded() { release(cancelled: true) }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        if held { release(cancelled: false) } else { press() }
        return true
    }
}
