import SwiftUI

struct MessageCard: View {
    let message: LearningMessage
    let examplesTitle: String
    let onSpeak: () -> Void
    @State private var showsLiteralChunks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text(message.normalizedSourceText)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsLiteralChunks {
                    alignedChunks
                } else {
                    targetText
                }
            }

            if let examples = message.examples, !examples.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(examplesTitle)
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

            HStack {
                Spacer()
                literalToggleButton
                speakButton
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.black.opacity(0.08), lineWidth: 1)
        )
        .clipped()
    }

    private var speakButton: some View {
        Button(action: onSpeak) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.08))
                .foregroundStyle(.black)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play pronunciation")
    }

    private var literalToggleButton: some View {
        Button {
            showsLiteralChunks.toggle()
        } label: {
            Image(systemName: showsLiteralChunks ? "text.bubble.fill" : "text.bubble")
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(showsLiteralChunks ? 0.14 : 0.08))
                .foregroundStyle(.black)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showsLiteralChunks ? "Hide literal translation" : "Show literal translation")
    }

    private var alignedChunks: some View {
        FlowLayout(spacing: 8, lineSpacing: showsLiteralChunks ? 12 : 4) {
            ForEach(message.literalChunks) { chunk in
                VStack(alignment: .center, spacing: 3) {
                    Text(chunk.targetText)
                        .font(.custom("ChalkboardSE-Bold", size: targetFontSize))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    if showsLiteralChunks {
                        Text(chunk.literalText)
                            .font(.body)
                            .foregroundStyle(.black.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, showsLiteralChunks ? 8 : 2)
                .padding(.vertical, showsLiteralChunks ? 6 : 2)
                .background(showsLiteralChunks ? .black.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var targetText: some View {
        Text(message.targetText)
            .font(.custom("ChalkboardSE-Bold", size: targetFontSize))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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
