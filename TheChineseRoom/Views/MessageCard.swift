import SwiftUI

struct MessageCard: View {
    let message: LearningMessage
    let appStrings: AppStrings
    let notationSystem: PronunciationNotationSystem
    let isLoadingPronunciation: Bool
    let pronunciationFailed: Bool
    let isLoadingHanja: Bool
    let hanjaFailed: Bool
    let onRequestAnnotations: () -> Void
    let onSpeak: () -> Void
    var maximumHeight: CGFloat = 520
    var isCurrentCard = true
    var revealProgress: CGFloat = 1
    var previewEdge: VerticalEdge = .top
    @State private var showsAnnotations = false

    var body: some View {
        MessageCardRevealLayout(progress: revealProgress, edge: previewEdge, visibleHeight: max(0, maximumHeight - PencilRectangle.contentInset * 2)) {
            InkText(message.normalizedSourceText)
                .appFont(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    if showsAnnotations {
                        alignedChunks
                    } else {
                        targetText
                    }
                    if showsAnnotations && (isLoadingPronunciation || isLoadingHanja) {
                        ProgressView()
                    }
                    if showsAnnotations && hanjaFailed {
                        InkText(appStrings.hanjaUnavailable)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if showsAnnotations && pronunciationFailed {
                        InkText(appStrings.pronunciationUnavailable)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleAnnotationsAndPlay()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    toggleAnnotationsAndPlay()
                }

                if let examples = message.examples, !examples.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        InkText(appStrings.examplesTitle)
                            .appFont(.headline)
                        ForEach(examples) { example in
                            VStack(alignment: .leading, spacing: 4) {
                                InkText(example.sourceText)
                                    .appFont(.subheadline)
                                InkText(example.targetText)
                                    .appFont(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
            .opacity(Double(revealProgress * revealProgress))

        }
        .padding(PencilRectangle.contentInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onChange(of: isCurrentCard) { _, isCurrent in
            if !isCurrent {
                showsAnnotations = false
            }
        }
    }

    private func toggleAnnotationsAndPlay() {
        showsAnnotations.toggle()
        if showsAnnotations { onRequestAnnotations() }
        onSpeak()
    }

    private func pronunciationLabel(_ text: String?) -> some View {
        let value = text ?? (notationSystem == .pinyin || pronunciationFailed ? "—" : notationSystem.placeholder)
        return InkText(value)
            .appFont(.caption)
            .foregroundStyle(Color.chineseRoomInk)
            .accessibilityLabel(text ?? (notationSystem == .pinyin || pronunciationFailed
                ? appStrings.pronunciationUnavailable : appStrings.pronunciationPlaceholder))
    }

    @ViewBuilder
    private var alignedChunks: some View {
        let units = PronunciationLayout.units(
                text: message.targetText,
                system: notationSystem,
                japanesePronunciation: message.japanesePronunciation,
                ipaPronunciation: message.ipaPronunciation
            )
        let groups = PronunciationLayout.groups(text: message.targetText, units: units, chunks: message.literalChunks)
        if message.literalChunks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                pronunciationFlow(units)
                hanjaLabels(for: units)
                InkText(appStrings.literalUnavailable)
                    .appFont(.body)
                    .foregroundStyle(Color.chineseRoomInk)
            }
        } else if let groups {
            FlowLayout(spacing: 8, lineSpacing: 12) {
                ForEach(groups) { group in
                    VStack(spacing: 3) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(group.units) { unit in
                                pronunciationUnit(unit)
                            }
                        }
                        hanjaLabels(for: group.units)
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(group.chunks) { chunk in
                                InkText(chunk.literalText)
                                    .appFont(.subheadline)
                                    .foregroundStyle(Color.chineseRoomInk)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(Color.chineseRoomInk.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // If legacy chunk formatting cannot be mapped, keep pronunciation aligned
                // to the whole sentence instead of assigning it to the wrong literal chunk.
                pronunciationFlow(units)
                hanjaLabels(for: units)
                FlowLayout(spacing: 8, lineSpacing: 12) {
                    ForEach(message.literalChunks) { chunk in
                        VStack(spacing: 3) {
                            InkText(chunk.targetText)
                                .appExpressionFont(size: annotationFontSize)
                            InkText(chunk.literalText)
                                .appFont(.subheadline)
                                .foregroundStyle(Color.chineseRoomInk)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(Color.chineseRoomInk.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }

    private func hanjaLabels(for units: [PronunciationUnit]) -> some View {
        let start = units.first?.range.location ?? 0
        let end = units.last.map { NSMaxRange($0.range) } ?? 0
        let annotations = (message.hanjaAnnotations ?? []).filter { $0.offset >= start && $0.offset < end }
        return ForEach(annotations) { annotation in
            InkText("\(annotation.surface) · \(annotation.hanja)")
                .appFont(.caption)
                .foregroundStyle(Color.chineseRoomInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pronunciationFlow(_ units: [PronunciationUnit]) -> some View {
        FlowLayout(spacing: 0, lineSpacing: 8) {
            ForEach(units) { unit in
                pronunciationUnit(unit)
            }
        }
    }

    private func pronunciationUnit(_ unit: PronunciationUnit) -> some View {
        VStack(spacing: 3) {
            if unit.needsNotation {
                pronunciationLabel(unit.notation)
            } else {
                InkText(" ").appFont(.caption).accessibilityHidden(true)
            }
            InkText(unit.text)
                .appExpressionFont(size: annotationFontSize)
        }
        .fixedSize()
    }

    private var targetText: some View {
        InkText(message.targetText)
            .appExpressionFont(size: targetFontSize)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var annotationFontSize: CGFloat {
        message.targetText.count > 60 ? 24 : 28
    }

    private var targetFontSize: CGFloat {
        let count = message.targetText.count

        switch count {
        case 0...18:
            return 46
        case 19...34:
            return 40
        default:
            return 35
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let boundsWidth = proposal.width ?? 0
        let rows = rows(in: boundsWidth, subviews: subviews)
        return CGSize(
            width: boundsWidth,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(in: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(element.size)
                )
                x += element.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentRow.width == 0 ? size.width : currentRow.width + spacing + size.width

            if proposedWidth > maxWidth, !currentRow.elements.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.add(subview: subview, size: size, spacing: spacing)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct Row {
        var elements: [(subview: LayoutSubview, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func add(subview: LayoutSubview, size: CGSize, spacing: CGFloat) {
            width += elements.isEmpty ? size.width : spacing + size.width
            height = max(height, size.height)
            elements.append((subview, size))
        }
    }
}

// The title remains the same view throughout paging; only its position changes.
private struct MessageCardRevealLayout: Layout {
    var progress: CGFloat
    let edge: VerticalEdge
    let visibleHeight: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let contentProposal = ProposedViewSize(width: width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(contentProposal).height }
        return CGSize(width: width, height: heights.reduce(0, +) + 14)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let titleSize = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let progress = min(1, max(0, progress))
        let previewOffset = edge == .bottom ? max(0, min(bounds.height, visibleHeight) - titleSize.height) : 0
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + previewOffset * (1 - progress)),
            proposal: ProposedViewSize(titleSize)
        )
        let contentTop = bounds.minY + titleSize.height + 14
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: contentTop),
            proposal: ProposedViewSize(width: bounds.width, height: max(0, bounds.maxY - contentTop))
        )
    }
}

/// One piece of paper survives loading, dictation and the finished message.
struct MessagePaper<Content: View>: View {
    let seed: UUID
    let maximumHeight: CGFloat
    var resetScroll = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        CappedCardScroll(maximumHeight: maximumHeight, resetScroll: resetScroll, content: content)
            .background { NotebookRules(seed: seed) }
            .background(Color.chineseRoomCard, in: PencilRectangleShape(seed: seed))
            .clipShape(PencilRectangleShape(seed: seed))
            .overlay(PencilRectangle(seed: seed))
    }
}

/// Measures intrinsic content height so short cards stay compact. Only overflow scrolls.
struct CappedCardScroll<Content: View>: View {
    let maximumHeight: CGFloat
    var resetScroll = false
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .id("card-top")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard contentHeight != height else { return }
                        if contentHeight == 0 || reduceMotion {
                            contentHeight = height
                        } else {
                            // The paper extends below its local top; the centered parent
                            // smoothly lifts it by half the added height at the same time.
                            withAnimation(.smooth(duration: 0.45)) { contentHeight = height }
                        }
                    }
            }
            .frame(height: min(maximumHeight, contentHeight > 0 ? contentHeight : 120))
            .scrollDisabled(contentHeight <= maximumHeight || resetScroll)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: resetScroll) { _, reset in
                if reset { reader.scrollTo("card-top", anchor: .top) }
            }
        }
    }
}
