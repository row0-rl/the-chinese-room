import SwiftUI
import UIKit
import PencilKit

struct MessageHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var dictationStartTask: Task<Void, Never>?
    let store: MessageStore
    let rooms: RoomStore
    let appStrings: AppStrings
    @State private var inputText = ""
    @State private var showsKeyboardInput = false
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
                    cardStack(height: cardViewportHeight)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 8)
                    if store.usesLocalMessages {
                        Text(appStrings.localTitle).appFont(.caption)
                            .accessibilityLabel(appStrings.localLabel)
                    }
                    inputArea
                }
            }

            if showsKeyboardInput { keyboardDismissLayer }
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
        .onChange(of: showsKeyboardInput || showsSettings) { _, presented in
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
        .onChange(of: rooms.currentRoomID) { _, _ in
            inputText = ""
            showsKeyboardInput = false
            isInputFocused = false
            cancelHeldDictation()
            recenterCardPager()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView(store: store, rooms: rooms)
        }
    }

    private var settingsButton: some View {
        HStack {
            Spacer()
            Button {
                cancelHeldDictation()
                dismissKeyboardMode()
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
            .accessibilityIdentifier("settings")
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

    private func cardStack(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let viewportHeight = proxy.size.height
            let previousStride = abs(cardPosition(-1, viewportHeight: viewportHeight))
            let nextStride = cardPosition(1, viewportHeight: viewportHeight)
            let destination = cardDragOffset > 0 ? -1 : 1
            let progress = min(1, abs(cardDragOffset) / max(1, destination == -1 ? previousStride : nextStride))

            ZStack {
                ForEach(visibleCards) { card in
                    let restingOffset = cardPlacementOffset(card.position, viewportHeight: viewportHeight)
                    let destinationOffset = cardPlacementOffset(card.position, centeredAt: destination, viewportHeight: viewportHeight)
                    let offset = restingOffset + (destinationOffset - restingOffset) * progress
                    MessagePaper(seed: card.id, maximumHeight: maximumCardHeight(in: viewportHeight), resetScroll: card.position != 0) {
                        Group {
                            if let message = card.message {
                                messageCard(
                                    message,
                                    revealProgress: card.position == 0 ? 1 - progress : (card.position == destination ? progress : 0),
                                    previewEdge: offset < 0 ? .bottom : .top,
                                    maximumHeight: maximumCardHeight(in: viewportHeight)
                                )
                                .transition(.opacity)
                            } else {
                                loadingCardContent(text: card.dictationText)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: card.message != nil)
                    }
                    .frame(width: proxy.size.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        cardHeights[card.id] = height
                    }
                    .frame(height: viewportHeight, alignment: card.position > 0 ? .top : (card.position < 0 ? .bottom : .center))
                    .offset(y: offset)
                    .allowsHitTesting(card.position == 0 && !isPaging && store.pendingDictationText == nil)
                    .accessibilityHidden(card.position != 0)
                }
            }
            .frame(width: proxy.size.width, height: viewportHeight)
            .contentShape(Rectangle())
            .clipped()
            .mask(cardStackFadeMask)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .updating($isDraggingCard) { value, dragging, _ in
                        if store.pendingDictationText == nil && !isPaging && !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) {
                            dragging = true
                        }
                    }
                    .onChanged { value in
                        guard store.pendingDictationText == nil, !isPaging, !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) else { return }
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
                        guard store.pendingDictationText == nil, !isPaging, !scrollsInsideCard(value.startLocation, viewportHeight: viewportHeight) else { return }
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

    /// Preview cards grow away from the visible edge. Their fixed viewport-sized
    /// wrapper keeps resizing separate from the pager's travel to the center.
    private func cardPlacementOffset(_ position: Int, centeredAt center: Int = 0, viewportHeight: CGFloat) -> CGFloat {
        let anchor: CGFloat = position > 0 ? 0 : (position < 0 ? 1 : 0.5)
        let relativePosition = position - center
        if relativePosition == 0 {
            return (viewportHeight - cardHeight(at: position)) * (0.5 - anchor)
        }

        let direction = relativePosition > 0 ? 1 : -1
        var edge: CGFloat = direction > 0 ? viewportHeight - 56 : 56
        if abs(relativePosition) > 1 {
            for step in 1..<abs(relativePosition) {
                edge += CGFloat(direction) * (cardHeight(at: center + step * direction) + 12)
            }
        }
        // At rest the next card's top is exactly viewportHeight - 56, regardless
        // of either its measured height or its animated presentation height.
        if direction > 0, anchor == 0 { return edge }
        if direction < 0, anchor == 1 { return edge - viewportHeight }
        let height = cardHeight(at: position)
        let top = direction > 0 ? edge : edge - height
        return top - anchor * (viewportHeight - height)
    }

    private func cardHeight(at position: Int) -> CGFloat {
        guard let card = visibleCards.first(where: { $0.position == position }) else { return 120 }
        return cardHeights[card.id] ?? (card.message == nil ? 120 : 180)
    }

    private var visibleCards: [PresentedMessageCard] {
        let isDictation = store.pendingDictationText != nil
        let isPending = isDictation || store.isShowingBlankCard
        return (-2...2).compactMap { position in
            if position == 0, isPending {
                return PresentedMessageCard(
                    id: isDictation ? store.pendingDictationID : store.nextRandomCardID,
                    position: position, dictationText: store.pendingDictationText
                )
            }
            let sourcePosition = isPending && position < 0 ? position + 1 : position
            if !(isPending && position > 0), let message = store.cardMessage(at: sourcePosition) {
                return PresentedMessageCard(id: message.id, position: position, message: message)
            }
            guard position > 0 else { return nil }
            let precedingMessage = store.cardMessage(at: position - 1)
            // Once prepared, the preceding card already owns nextRandomCardID.
            // Its following placeholder must keep a separate identity.
            let isNextPaper = (!isPending && precedingMessage != nil && precedingMessage?.id != store.nextRandomCardID)
                || (isDictation && position == 1)
            return PresentedMessageCard(
                id: isNextPaper ? store.nextRandomCardID : Self.previewPaperIDs[position - 1],
                position: position
            )
        }
    }

    private static let previewPaperIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    ]

    private func loadingCardContent(text: String?) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if let text {
                if text.isEmpty {
                    WritingWave().frame(width: 180, height: 24)
                } else {
                    InkText(MessagePunctuation.clean(text))
                        .appFont(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                WritingWave().frame(height: 64)
                    .accessibilityLabel(appStrings.loadingMessageLabel)
            } else {
                WritingWave().frame(height: 32)
                    .frame(height: 56, alignment: .top)
                    .accessibilityLabel(appStrings.loadingMessageLabel)
            }
        }
        .padding(PencilRectangle.contentInset)
        .frame(maxWidth: .infinity, alignment: .leading)
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

            DictationPressButton(
                label: appStrings.holdToSpeakLabel,
                enabled: !store.isGenerating && !store.isTranscribing,
                foreground: .chineseRoomInk,
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

private struct PresentedMessageCard: Identifiable {
    let id: UUID
    let position: Int
    var message: LearningMessage?
    var dictationText: String?
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
    @State private var voicePreviewError: String?
    @State private var voicePreviewTask: Task<Void, Never>?
    @State private var isPreparingVoicePreview = false
    @State private var selectedVoiceIdentifier: String?
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    let store: MessageStore
    let rooms: RoomStore
    private var source: LanguageProfile { store.currentLanguageMode.source }
    private var target: LanguageProfile { store.currentLanguageMode.target }
    private var appStrings: AppStrings { AppLocale.forLanguage(source).strings }

    init(store: MessageStore, rooms: RoomStore) {
        self.store = store
        self.rooms = rooms
        _selectedVoiceIdentifier = State(
            initialValue: store.availableVoices(for: store.currentLanguageMode)
                .first { $0.id == store.selectedVoiceIdentifier(for: store.currentLanguageMode) }?.id
        )
    }

    private var roomMode: LanguageMode {
        LanguageMode(source: source, target: target)
    }

    private var voices: [SpeechVoice] {
        store.availableVoices(for: roomMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        RoomsManagementView(rooms: rooms, store: store)
                    } label: {
                        Label(appStrings.roomsTitle, systemImage: "rectangle.stack")
                            .appFont(.body)
                    }
                    if let room = rooms.currentRoom {
                        RoomLabel(room: room, strings: appStrings)
                    }
                } header: {
                    Text(appStrings.currentRoomTitle).appFont(.footnote)
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
                        Picker(appStrings.voiceTitle, selection: Binding(
                            get: { selectedVoiceIdentifier },
                            set: { selectVoice($0) }
                        )) {
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
            .onChange(of: store.currentLanguageMode) { _, _ in
                voicePreviewTask?.cancel()
                voicePreviewError = nil
                isPreparingVoicePreview = false
                loadVoiceForRoom()
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
                        store.updateVoiceIdentifier(selectedVoiceIdentifier, for: roomMode)
                        dismiss()
                    }
                    .appFont(.body)
                }
            }
        }
    }

    private func loadVoiceForRoom() {
        selectedVoiceIdentifier = voices.first { $0.id == store.selectedVoiceIdentifier(for: roomMode) }?.id
    }

    private func selectVoice(_ identifier: String?) {
        guard identifier != selectedVoiceIdentifier else { return }
        selectedVoiceIdentifier = identifier
        voicePreviewTask?.cancel()
        voicePreviewError = nil
        isPreparingVoicePreview = true
        let mode = roomMode
        voicePreviewTask = Task {
            defer { if !Task.isCancelled { isPreparingVoicePreview = false } }
            do {
                try await store.previewVoice(identifier, for: mode)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                voicePreviewError = error.localizedDescription
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
    private let pencilOutline = UIImageView()
    private let titleLabel = UILabel()
    private let microphoneImage = UIImage(named: "FuzzyMicrophone")?.withRenderingMode(.alwaysTemplate)
    private let feedback = UIImpactFeedbackGenerator(style: .heavy)
    private var held = false
    private var pressID = UUID()
    private var pencilRequest: PencilButtonRequest?
    private var pencilTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        pencilOutline.tintColor = .chineseRoomInk
        pencilOutline.isUserInteractionEnabled = false
        pencilOutline.isAccessibilityElement = false
        icon.image = microphoneImage
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.isUserInteractionEnabled = false
        titleLabel.isAccessibilityElement = false
        addSubview(pencilOutline)
        addSubview(titleLabel)
        addSubview(icon)
        NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { pencilTask?.cancel() }

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
        pencilOutline.frame = bounds
        let request = PencilButtonRequest(size: bounds.size, scale: traitCollection.displayScale)
        if request.pixelWidth > 0, request.pixelHeight > 0, request != pencilRequest {
            pencilRequest = request
            pencilTask?.cancel()
            pencilTask = Task { @MainActor [weak self] in
                guard let image = await PencilButtonRenderer.shared.image(for: request),
                      !Task.isCancelled else { return }
                self?.pencilOutline.image = image.withRenderingMode(.alwaysTemplate)
            }
        }
        let iconSize = min(24, max(0, bounds.height - 16))
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
            pencilOutline.tintColor = .systemRed
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
            pencilOutline.tintColor = .chineseRoomInk
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

private struct PencilButtonRequest: Hashable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: CGFloat

    init(size: CGSize, scale: CGFloat) {
        self.scale = max(1, scale)
        pixelWidth = Int((max(0, size.width) * self.scale).rounded())
        pixelHeight = Int((max(0, size.height) * self.scale).rounded())
    }

    var size: CGSize { CGSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(pixelHeight) / scale) }
    var key: NSString { "\(pixelWidth):\(pixelHeight):\(scale)" as NSString }
}

/// One seeded pencil outline, reused for every touch state and reproduced on launch.
private actor PencilButtonRenderer {
    static let shared = PencilButtonRenderer()
    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1_024 * 1_024
        return cache
    }()

    func image(for request: PencilButtonRequest) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let image = cache.object(forKey: request.key) { return image }
        let size = request.size
        guard size.width > 0, size.height > 0 else { return nil }
        let outline = PencilRectangle.outlinePath(
            seed: UUID(uuidString: "7CA953B1-D4E6-408F-8CA9-53B1D4E6208F")!, size: size,
            cornerRadius: 6, cornerJitter: 1.5, lineWidth: 5, wobble: 1
        ).cgPath
        var locations: [CGPoint] = []
        outline.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: locations.append(element.pointee.points[0])
            default: break
            }
        }
        if let first = locations.first { locations.append(first) }
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: Double(index) * 0.01,
                size: CGSize(width: 5, height: 5),
                opacity: 1, force: 1, azimuth: .pi / 12, altitude: .pi / 2
            )
        }
        let stroke = PKStroke(
            ink: PKInk(.pencil, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)),
            randomSeed: 0xD4E6208F
        )
        let image: UIImage? = autoreleasepool {
            var result: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                result = PKDrawing(strokes: [stroke]).image(from: CGRect(origin: .zero, size: size), scale: request.scale)
            }
            return result
        }
        guard let image, !Task.isCancelled else { return nil }
        cache.setObject(image, forKey: request.key, cost: request.pixelWidth * request.pixelHeight * 4)
        return image
    }

}
