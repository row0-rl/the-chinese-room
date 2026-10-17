import SwiftUI

struct SavedMessagesView: View {
    @State private var previewItem: SavedMessageItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPeeking = false
    @State private var poppedID: String?
    @State private var poppedAnchorOffset: CGFloat?
    @State private var contentHeights: [String: CGFloat] = [:]
    @State private var visibleStackRect = CGRect.zero
    @State private var lastPeekTranslation: CGFloat = 0
    @State private var scrub = SavedMessageScrub()
    @State private var suppressTapUntil = Date.distantPast
    @State private var hapticTick = 0

    private func stackLayout(for displayedItems: [SavedMessageItem]) -> SavedMessageStackLayout {
        SavedMessageStackLayout(count: displayedItems.count,
            expandedIndex: displayedItems.firstIndex { $0.id == poppedID },
            expandedHeight: poppedID.flatMap { contentHeights[$0] } ?? SavedMessageStackLayout.cardHeight,
            cardHeights: displayedItems.map { contentHeights[$0.id] ?? SavedMessageStackLayout.cardHeight },
            anchorOffset: poppedAnchorOffset)
    }

    private var popAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.24, bounce: 0.08)
    }
    let store: MessageStore
    let rooms: RoomStore
    let strings: AppStrings

    private var items: [SavedMessageItem] {
        let saved = SavedMessageCollection.items(modeID: store.currentLanguageMode.id,
            messages: store.messages, roomTitle: rooms.currentRoom?.title(strings: strings) ?? "")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--saved-messages-preview") {
            let samples = ["I need a little more time", "Where did you find this?", "Let's go for a walk", "I almost forgot", "That sounds like a good idea", "Could you say that again?"]
            return saved + samples.enumerated().map { index, text in
                let longPreview = ProcessInfo.processInfo.arguments.contains("--saved-long-preview") && index == 2
                let source = longPreview ? "Where did you find this? I have been looking for something like this all week" : text
                return SavedMessageItem(modeID: store.currentLanguageMode.id, roomTitle: rooms.currentRoom?.title(strings: strings) ?? "",
                    message: LearningMessage(id: UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", index))!,
                        sourceText: source, normalizedSourceText: source, targetText: store.currentMessage.targetText,
                        literalMeaning: longPreview ? "A longer expression with its full details laid out on the same sheet." : store.currentMessage.literalMeaning, isSaved: true))
            }
        }
        #endif
        return saved
    }

    var body: some View {
        let displayedItems = items
        let layout = stackLayout(for: displayedItems)
        Group {
            if displayedItems.isEmpty {
                ContentUnavailableView(strings.savedMessagesTitle, systemImage: "bookmark",
                    description: Text(strings.savedMessagesEmpty))
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                            Button {
                                guard !isPeeking, Date() >= suppressTapUntil else { return }
                                previewItem = item
                            } label: {
                                SavedStackCardContent(message: item.message)
                                    .transaction { $0.animation = nil }
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                        if contentHeights[item.id] != height { contentHeights[item.id] = height }
                                    }
                                    .frame(height: layout.height(at: index), alignment: .topLeading)
                                    .background { NotebookRules(seed: item.message.id) }
                                    .background(Color.chineseRoomSurface)
                                    .clipShape(PencilStackSheetShape(seed: item.message.id,
                                        stackHeight: layout.height - layout.topOffset,
                                        rowOffset: layout.offset(at: index) - layout.topOffset,
                                        isFirst: index == 0))
                                    .overlay(alignment: .top) {
                                        if index > 0 {
                                            PencilStackDivider(seed: item.message.id,
                                                stackHeight: layout.height - layout.topOffset,
                                                rowOffset: layout.offset(at: index) - layout.topOffset)
                                                .frame(height: 44)
                                        }
                                    }
                                    .clipped()
                            }
                            .buttonStyle(.plain)
                            .frame(height: layout.advance(at: index), alignment: .top)
                            .contentShape(Rectangle())
                            .highPriorityGesture(peekGesture(startingAt: item.id))
                            .accessibilityLabel(item.message.normalizedSourceText)
                            .accessibilityValue(item.message.targetText)
                            .accessibilityHint(strings.savedMessageOpenHint)
                            .zIndex(Double(index))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    // Clip the overlapping sheets together, then draw the two
                    // side edges once. Individual card outlines would diverge
                    // at every join, even if they used the same pencil seed.
                    .clipShape(PencilRectangleShape(seed: PencilRectangle.placeholderSeed))
                    .overlay { PencilRectangle(seed: PencilRectangle.placeholderSeed) }
                    .offset(y: layout.topOffset)
                    .frame(height: max(layout.height, poppedID == nil ? 0 : visibleStackRect.maxY), alignment: .top)
                    .coordinateSpace(name: "saved-message-stack")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollDisabled(isPeeking)
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                    visibleStackRect = rect
                }
                .accessibilityIdentifier("saved-message-stack")
            }
        }
        .background(Color.chineseRoomBackground.ignoresSafeArea())
        .foregroundStyle(Color.chineseRoomInk)
        .navigationTitle(strings.savedMessagesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .font(.body)
        .tint(Color.chineseRoomInk)
        .navigationDestination(item: $previewItem) { item in
            SavedExpressionDetail(item: item, strings: strings) { unsave(item) }
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
        .onChange(of: isPeeking) { _, active in
            if !active { endPeek() }
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if let poppedID, !ids.contains(poppedID) { endPeek() }
        }
        .onChange(of: store.currentLanguageMode.id) { _, _ in
            previewItem = nil
            endPeek()
        }
        .onDisappear { endPeek() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--saved-pop-preview") {
                try? await Task.sleep(for: .milliseconds(300))
                let candidate = ProcessInfo.processInfo.arguments.contains("--saved-long-preview")
                    ? items.first(where: { $0.message.normalizedSourceText.count > 70 })
                    : (items.count > 2 ? items[2] : items.first)
                if let candidate {
                    let down = ProcessInfo.processInfo.arguments.contains("--saved-scrub-down-preview")
                    popCard(candidate.id, verticalDelta: down ? 180 : 0,
                        fingerY: down ? visibleStackRect.minY + visibleStackRect.height * 0.65 : nil)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--saved-detail-preview"), previewItem == nil, let first = items.first {
                previewItem = first
            }
            #endif
        }
    }

    private func peekGesture(startingAt initialID: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("saved-message-stack")))
            .updating($isPeeking) { value, active, _ in
                if case .second(true, _) = value { active = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                // A completed hold can precede the drag's first location.
                // Expand the touched row immediately, without requiring motion.
                guard let drag else {
                    popCard(initialID)
                    return
                }
                if poppedID == nil { popCard(initialID) }
                let delta = drag.translation.height - lastPeekTranslation
                lastPeekTranslation = drag.translation.height
                let displayedItems = items
                guard let index = displayedItems.firstIndex(where: { $0.id == poppedID }),
                      let next = scrub.selection(after: delta, current: index, count: displayedItems.count) else { return }
                popCard(displayedItems[next].id, verticalDelta: delta, fingerY: drag.location.y)
            }
            .onEnded { _ in endPeek() }
    }

    private func popCard(_ id: String, verticalDelta: CGFloat = 0, fingerY: CGFloat? = nil) {
        // Position is captured only when a different sheet becomes selected.
        // Further motion over this sheet must not move it or retrigger haptics.
        guard poppedID != id else { return }
        let displayedItems = items
        guard let index = displayedItems.firstIndex(where: { $0.id == id }) else { return }
        let layout = stackLayout(for: displayedItems)
        let anchor = layout.selectionAnchor(at: index, verticalDelta: verticalDelta, fingerY: fingerY)
        suppressTapUntil = .distantFuture
        withAnimation(popAnimation) {
            poppedAnchorOffset = anchor
            poppedID = id
        }
        hapticTick += 1
    }

    private func endPeek() {
        lastPeekTranslation = 0
        scrub = SavedMessageScrub()
        guard poppedID != nil else { return }
        suppressTapUntil = Date().addingTimeInterval(0.35)
        let settle: Animation = reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.36, bounce: 0.22)
        withAnimation(settle) {
            poppedID = nil
            poppedAnchorOffset = nil
        }
    }

    private func unsave(_ item: SavedMessageItem) -> Bool {
        guard item.modeID == store.currentLanguageMode.id,
              store.messages.contains(where: { $0.id == item.message.id && $0.isSaved }) else { return false }
        store.toggleSaved(for: item.message.id)
        return true
    }

}

private struct SavedStackCardContent: View {
    let message: LearningMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text(message.normalizedSourceText)
                .appFont(.title3)
            Text(message.targetText)
                .appExpressionFont(size: 32)
                .fixedSize(horizontal: false, vertical: true)
            if !message.literalMeaning.isEmpty {
                Text(message.literalMeaning).appFont(.body)
            }
            ForEach(message.examples ?? []) { example in
                VStack(alignment: .leading, spacing: 6) {
                    Text(example.sourceText).appFont(.body)
                    Text(example.targetText).appFont(.body)
                }
            }
        }
        .foregroundStyle(Color.chineseRoomInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 22)
    }
}

private struct SavedExpressionDetail: View {
    @Environment(\.dismiss) private var dismiss
    let item: SavedMessageItem
    let strings: AppStrings
    let unsave: () -> Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.roomTitle).font(.caption).foregroundStyle(.secondary)
                    MessagePaper(seed: item.message.id, maximumHeight: max(220, proxy.size.height - 100),
                                 appStrings: strings) {
                        VStack(alignment: .leading, spacing: 24) {
                            InkText(item.message.normalizedSourceText).appFont(.title3)
                            InkText(item.message.targetText).appExpressionFont(size: 36)
                            if !item.message.literalMeaning.isEmpty {
                                InkText(item.message.literalMeaning).appFont(.body)
                            }
                            ForEach(item.message.examples ?? []) { example in
                                VStack(alignment: .leading, spacing: 6) {
                                    InkText(example.sourceText).appFont(.body)
                                    InkText(example.targetText).appFont(.body)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(26)
                    }
                }
                .padding(20)
            }
        }
        .background(Color.chineseRoomBackground.ignoresSafeArea())
        .foregroundStyle(Color.chineseRoomInk)
        .navigationTitle(strings.savedMessagesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(strings.unsaveExpression, systemImage: "bookmark.slash") {
                    if unsave() { dismiss() }
                }
            }
        }
    }
}
