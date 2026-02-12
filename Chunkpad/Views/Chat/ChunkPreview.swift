import SwiftUI

struct ChunkPreview: View {
    let scoredChunk: ScoredChunk
    /// Called when the user toggles this chunk on/off.
    var onToggle: () -> Void = {}

    @State private var isExpanded = false

    private var chunk: Chunk { scoredChunk.chunk }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(chunk.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 3)

            Text(chunk.sourcePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(GlassTokens.Padding.element)
        .opacity(scoredChunk.isIncluded ? 1 : 0.5)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }

    private var header: some View {
        HStack {
            // Include/exclude toggle
            GlassIconButton(
                systemName: scoredChunk.isIncluded ? "checkmark.circle.fill" : "circle",
                size: 24
            ) {
                onToggle()
            }

            Text(chunk.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

            Spacer()

            // Relevance score pill
            GlassPill {
                Text(scoredChunk.relevancePercent)
                    .foregroundStyle(scoreColor)
            }

            if let slideNumber = chunk.slideNumber {
                GlassPill {
                    Label("Slide \(slideNumber)", systemImage: "rectangle.on.rectangle")
                }
            }

            GlassIconButton(systemName: "chevron.down", size: 24) {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            }
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    /// Color based on relevance: green for high, orange for mid, red for low.
    private var scoreColor: Color {
        let score = scoredChunk.relevanceScore
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }
}
