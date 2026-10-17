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
                .padding(.trailing, 22)
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
    var isSaved = false
    // Loading and loaded feed cards share the renderer and its cached texture.
    var usesContinuousOutline = false
    let appStrings: AppStrings
    var onToggleSaved: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasFoldedMessageCorner") private var hasFoldedCorner = false
    @GestureState private var cornerDragTranslation: CGSize?
    @State private var feedbackID: UUID?
    @State private var feedback: String?

    private var drawsCurledOutline: Bool { usesContinuousOutline || onToggleSaved != nil || isSaved }

    private var cornerDragProgress: CGFloat? {
        if cornerDragTranslation != nil || curlTranslation != .zero {
            return PaperCornerInteraction.progress(isSaved: isSaved, translation: curlTranslation)
        }
        return nil
    }
    private var curlTranslation: CGSize {
        #if DEBUG
        if cornerDragTranslation == nil {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--corner-joins-up-preview") { return CGSize(width: -70, height: -60) }
            if args.contains("--corner-joins-down-preview") { return CGSize(width: -70, height: 60) }
            if args.contains("--corner-short-down-preview") { return CGSize(width: 70, height: 230) }
            if args.contains("--corner-large-preview") { return CGSize(width: -140, height: 140) }
        }
        #endif
        return cornerDragTranslation ?? .zero
    }
    private var curlDisplacement: CGSize {
        PaperCornerInteraction.displacement(foldSize: foldSize, translation: curlTranslation)
    }
    private var foldProgress: CGFloat { cornerDragProgress ?? (isSaved ? 1 : 0) }
    private var foldSize: CGFloat { PaperCornerInteraction.savedFoldSize * foldProgress }

    private var paperHeightLimit: CGFloat {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--corner-short-down-preview") { return min(140, maximumHeight) }
        #endif
        return maximumHeight
    }

    var body: some View {
        CappedCardScroll(maximumHeight: paperHeightLimit, resetScroll: resetScroll, content: content)
            .background { NotebookRules(seed: seed) }
            .background(Color.chineseRoomSurface, in: PencilRectangleShape(seed: seed))
            .clipShape(PencilRectangleShape(seed: seed))
            .mask {
                PaperCylinderCutout(seed: seed, displacement: drawsCurledOutline ? curlDisplacement : .zero, includeFront: true)
            }
            .overlay {
                if !drawsCurledOutline {
                    PencilRectangle(seed: seed)
                }
            }
            .overlay(alignment: .topTrailing) {
                if drawsCurledOutline {
                    PaperCylinderSurface(seed: seed, displacement: curlDisplacement)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.16), value: isSaved)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.5, bounce: 0.28), value: cornerDragProgress == nil)
            .overlay(alignment: .topTrailing) {
                if let onToggleSaved, !resetScroll {
                    Color.clear
                        .frame(width: PaperCornerInteraction.hitSize, height: PaperCornerInteraction.hitSize)
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 6)
                                .exclusively(before: TapGesture())
                                .updating($cornerDragTranslation) { value, translation, transaction in
                                    guard case .first(let drag) = value else { return }
                                    transaction.animation = nil
                                    translation = drag.translation
                                }
                                .onEnded { value in
                                    if case .first(let drag) = value,
                                       !PaperCornerInteraction.shouldToggle(isSaved: isSaved, translation: drag.translation) {
                                        return
                                    }
                                    commitSaveToggle(onToggleSaved)
                                }
                        )
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { commitSaveToggle(onToggleSaved) }
                        .accessibilityLabel(isSaved ? appStrings.unsaveExpression : appStrings.saveExpression)
                        .accessibilityHint(isSaved ? appStrings.unfoldCornerHint : appStrings.foldCornerHint)
                        .accessibilityIdentifier("message-save-corner")
                }
            }
            .overlay(alignment: .topTrailing) {
                if onToggleSaved != nil, !resetScroll,
                   let label = feedback ?? (!hasFoldedCorner && !isSaved ? appStrings.foldCornerHint : nil) {
                    Text(label)
                        .appFont(.caption)
                        .foregroundStyle(Color.chineseRoomInk.opacity(0.7))
                        .padding(.trailing, 16)
                        .offset(y: -20)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .task(id: feedbackID) {
                guard feedbackID != nil else { return }
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                feedback = nil
            }
    }

    private func commitSaveToggle(_ action: () -> Void) {
        action()
        hasFoldedCorner = true
        feedback = isSaved ? appStrings.expressionUnsaved : appStrings.expressionSaved
        feedbackID = UUID()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Every visible edge and face is projected from the same bent paper surface.
private struct CylinderPaperGeometry {
    let vertices: [CGPoint]
    let cylinder: PaperCylinder
    init(seed: UUID, size: CGSize, displacement: CGSize) {
        var points: [CGPoint] = []
        PencilRectangleShape(seed: seed).path(in: CGRect(origin: .zero, size: size)).cgPath.applyWithBlock { element in
            if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint {
                points.append(element.pointee.points[0])
            }
        }
        // Sample the original edges before projection so curved silhouettes
        // stay smooth without rendering the surface as separate painted strips.
        var sampled: [CGPoint] = []
        if hypot(displacement.width, displacement.height) > 0.1, let last = points.last {
            for (a, b) in zip([last] + points, points) {
                let count = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y))))
                for i in 0..<count {
                    let t = CGFloat(i) / CGFloat(count)
                    sampled.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
        }
        vertices = hypot(displacement.width, displacement.height) <= 0.1 ? points : sampled
        let normal = CGVector(dx: -displacement.width, dy: -displacement.height)
        let tip = points.max { $0.x * normal.dx + $0.y * normal.dy < $1.x * normal.dx + $1.y * normal.dy } ?? CGPoint(x: size.width, y: 0)
        cylinder = PaperCylinder(corner: tip, displacement: displacement)
    }
    var crest: [CGPoint] {
        let distance = .pi * cylinder.radius / 2
        return cylinder.clip(vertices, at: distance, above: true)
            .filter { abs(cylinder.distance($0) - distance) < 0.001 }
            .map { cylinder.project($0).point }
    }
    static func path(_ points: [CGPoint], closed: Bool = true) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if closed { path.closeSubpath() }
        }
    }
}

private struct PaperCylinderCutout: Shape {
    let seed: UUID
    var displacement: CGSize
    var includeFront = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(displacement.width, displacement.height) }
        set { displacement = CGSize(width: newValue.first, height: newValue.second) }
    }
    func path(in rect: CGRect) -> Path {
        guard hypot(displacement.width, displacement.height) > 0.1 else { return Path(rect) }
        let paper = CylinderPaperGeometry(seed: seed, size: rect.size, displacement: displacement)
        // Mask only the bending half-plane; clipping to the pencil centerline
        // here would shave half the graphite off every unaffected card edge.
        let bounds = [CGPoint(x: -8, y: -8), CGPoint(x: rect.width + 8, y: -8),
                      CGPoint(x: rect.width + 8, y: rect.height + 8), CGPoint(x: -8, y: rect.height + 8)]
        // Keep one point of paper beneath the tangent join so independently
        // antialiased masks cannot expose a diagonal hairline of background.
        let flat = CylinderPaperGeometry.path(paper.cylinder.clip(bounds, at: 1, above: false))
        guard includeFront else { return flat }
        // The message UI continues across the front of the bend. Its mask
        // follows the visible paper silhouette, not the cylinder's start axis.
        let front = paper.cylinder.clip(paper.cylinder.clip(paper.vertices, at: 0, above: true),
                                       at: .pi * paper.cylinder.radius / 2, above: false)
        let projected = CylinderPaperGeometry.path(front.map { paper.cylinder.project($0).point })
        return flat.union(projected)
    }
}

private struct PaperCylinderSurface: View {
    let seed: UUID
    var displacement: CGSize

    var body: some View {
        GeometryReader { proxy in
            PaperCylinderSurfaceDrawing(seed: seed, paperSize: proxy.size, displacement: displacement)
        }
    }
}

/// GeometryReader supplies the destination size during a layout animation.
/// Interpolate that size explicitly so Canvas draws the same intermediate
/// paper bounds as the background and mask, rather than jumping ahead of them.
private struct PaperCylinderSurfaceDrawing: View, Animatable {
    let seed: UUID
    var paperSize: CGSize
    var displacement: CGSize
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(paperSize.width, paperSize.height),
                             AnimatablePair(displacement.width, displacement.height)) }
        set {
            paperSize = CGSize(width: newValue.first.first, height: newValue.first.second)
            displacement = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        let paper = CylinderPaperGeometry(seed: seed, size: paperSize, displacement: displacement)
        let cylinder = paper.cylinder
        let lifted = cylinder.clip(paper.vertices, at: 0, above: true)
        let isFlat = hypot(displacement.width, displacement.height) <= 0.1
        let back = isFlat ? [] : cylinder.clip(lifted, at: .pi * cylinder.radius / 2, above: true)
        let backFace = back.map { cylinder.project($0).point }
        let drawingBounds = cylinder.drawingBounds(vertices: paper.vertices, paperSize: paperSize)
        PencilCurledSheetOutline(seed: seed, paperSize: paperSize, vertices: paper.vertices,
                                cylinder: cylinder, crest: isFlat ? [] : paper.crest, backFace: backFace,
                                drawingBounds: drawingBounds)
            .frame(width: drawingBounds.width, height: drawingBounds.height)
            .offset(x: drawingBounds.minX, y: drawingBounds.minY)
    }
}

enum MessagePaperTransition {
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.3)
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
                            withAnimation(MessagePaperTransition.animation(reduceMotion: reduceMotion)) { contentHeight = height }
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

#if DEBUG
/// A deterministic surface for inspecting the actual paper and fold together.
struct MessagePaperFoldPreview: View {
    @State private var isSaved = true
    private let seed = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    var body: some View {
        VStack(spacing: 40) {
            MessagePaper(seed: seed, maximumHeight: 240, isSaved: isSaved,
                         appStrings: AppStrings(localeIdentifier: "en"),
                         onToggleSaved: { isSaved.toggle() }) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("I want to remember this").appFont(.title3)
                    Text("Je veux m’en souvenir").appExpressionFont(size: 35)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PencilRectangle.contentInset)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chineseRoomBackground)
    }
}

#Preview("Paper fold") { MessagePaperFoldPreview() }
#endif
