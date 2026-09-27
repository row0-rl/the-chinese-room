import SwiftUI

struct MessageCard: View {
    let message: LearningMessage
    let appStrings: AppStrings
    let notationSystem: PronunciationNotationSystem
    let isLoadingPronunciation: Bool
    let pronunciationFailed: Bool
    let onRequestPronunciation: () -> Void
    let onSpeak: () -> Void
    var isCurrentCard = true
    var revealProgress: CGFloat = 1
    var previewEdge: VerticalEdge = .top
    @State private var showsAnnotations = false

    var body: some View {
        MessageCardRevealLayout(progress: revealProgress, edge: previewEdge) {
            Text(message.normalizedSourceText)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    if showsAnnotations {
                        alignedChunks
                    } else {
                        targetText
                    }
                    if showsAnnotations && isLoadingPronunciation {
                        ProgressView()
                    }
                    if showsAnnotations && pronunciationFailed {
                        Text(appStrings.pronunciationUnavailable)
                            .font(.caption)
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
                        Text(appStrings.examplesTitle)
                            .font(.headline)
                        ForEach(examples) { example in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(example.sourceText)
                                    .font(.subheadline)
                                Text(example.targetText)
                                    .font(.subheadline.weight(.semibold))
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
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
        .clipped()
        .onChange(of: isCurrentCard) { _, isCurrent in
            if !isCurrent {
                showsAnnotations = false
            }
        }
    }

    private func toggleAnnotationsAndPlay() {
        showsAnnotations.toggle()
        if showsAnnotations { onRequestPronunciation() }
        onSpeak()
    }

    private func pronunciationLabel(_ text: String?) -> some View {
        let value = text ?? (notationSystem == .pinyin || pronunciationFailed ? "—" : notationSystem.placeholder)
        return Text(value)
            .font(.caption)
            .foregroundStyle(.black.opacity(0.6))
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
                Text(appStrings.literalUnavailable)
                    .font(.body)
                    .foregroundStyle(.black.opacity(0.7))
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
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(group.chunks) { chunk in
                                Text(chunk.literalText)
                                    .font(.subheadline)
                                    .foregroundStyle(.black.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // If legacy chunk formatting cannot be mapped, keep pronunciation aligned
                // to the whole sentence instead of assigning it to the wrong literal chunk.
                pronunciationFlow(units)
                FlowLayout(spacing: 8, lineSpacing: 12) {
                    ForEach(message.literalChunks) { chunk in
                        VStack(spacing: 3) {
                            Text(chunk.targetText)
                                .font(.custom("ChalkboardSE-Bold", size: annotationFontSize))
                            Text(chunk.literalText)
                                .font(.subheadline)
                                .foregroundStyle(.black.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
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
                Text(" ").font(.caption).accessibilityHidden(true)
            }
            Text(unit.text)
                .font(.custom("ChalkboardSE-Bold", size: annotationFontSize))
        }
        .fixedSize()
    }

    private var targetText: some View {
        Text(message.targetText)
            .font(.custom("ChalkboardSE-Bold", size: targetFontSize))
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
        let previewOffset = edge == .bottom ? max(0, bounds.height - titleSize.height) : 0
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
