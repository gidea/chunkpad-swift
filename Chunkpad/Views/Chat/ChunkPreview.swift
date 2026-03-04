import SwiftUI

/// A card displaying a single retrieved chunk with relevance score, feedback controls,
/// and collection metadata.
///
/// Used in the horizontal scroll strip below the chat to let users inspect and curate
/// the chunks that will be included in the LLM context before (re)generating a response.
///
/// **Callbacks**
/// - `onToggle`: include/exclude the chunk from the LLM context (per-session).
/// - `onFeedback`: persist a boost/hide signal (survives sessions via `chunk_feedback` table).
///   Pass `.neutral` to clear an existing signal (reverts to 1.0× multiplier).
///
/// **Visual states**
/// - Pinned: orange glass tint, orange "Pinned" pill.
/// - Boosted: green boost icon + "Boosted" pill (Task 16.4).
/// - Hidden: muted icon + "Hidden" pill + dimmed body text (Task 16.4).
/// - Collection: folder pill showing collection name when present (Task 13.8).
struct ChunkPreview: View {
    let scoredChunk: ScoredChunk
    /// Called when the user toggles this chunk in/out of the LLM context.
    var onToggle: () -> Void = {}
    /// Called when the user sets or clears persistent feedback for this chunk.
    /// Receives the requested `FeedbackType`; `.neutral` means "clear feedback".
    var onFeedback: (FeedbackType) -> Void = { _ in }

    @State private var isExpanded = false
    /// Drives the spring-pulse animation that fires when feedback changes.
    @State private var feedbackScale: CGFloat = 1.0

    private var chunk: Chunk { scoredChunk.chunk }
    /// Resolved feedback — nil stored as .neutral so switch/comparison is clean.
    private var feedback: FeedbackType { scoredChunk.feedbackType ?? .neutral }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(chunk.content)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? nil : 3)
                // Hidden chunks are dimmed to signal their dampened retrieval weight (Task 16.3)
                .opacity(feedback == .hide ? 0.6 : 1.0)

            Text(chunk.sourcePath)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(GlassTokens.Padding.element)
        .opacity(scoredChunk.isIncluded ? 1 : 0.5)
        .glassEffect(
            scoredChunk.isPinned ? .regular.tint(.orange) : .regular,
            in: .rect(cornerRadius: GlassTokens.Radius.element)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // ── Include/exclude toggle ─────────────────────────────────────────────
            GlassIconButton(
                systemName: scoredChunk.isIncluded ? "checkmark.circle.fill" : "circle",
                size: 24
            ) {
                onToggle()
            }

            // ── Boost button (Task 16.3) ───────────────────────────────────────────
            // Filled SF Symbol + green foreground when active; tapping an active
            // state reverts to neutral (undo gesture).
            GlassIconButton(
                systemName: feedback == .boost ? "hand.thumbsup.fill" : "hand.thumbsup",
                size: 24
            ) {
                applyFeedback(feedback == .boost ? .neutral : .boost)
            }
            .foregroundStyle(feedback == .boost ? Color.green : Color.secondary)
            .scaleEffect(feedbackScale)

            // ── Hide button (Task 16.3) ────────────────────────────────────────────
            GlassIconButton(
                systemName: feedback == .hide ? "eye.slash.fill" : "eye.slash",
                size: 24
            ) {
                applyFeedback(feedback == .hide ? .neutral : .hide)
            }
            .foregroundStyle(feedback == .hide ? Color.red : Color.secondary)
            .scaleEffect(feedbackScale)

            // Pinned indicator
            if scoredChunk.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Title — muted when hidden so the dampened state is immediately obvious
            Text(chunk.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(feedback == .hide ? Color.secondary : Color.primary)

            Spacer()

            // ── Collection badge (Task 13.8) ───────────────────────────────────────
            // Populated by hybridSearch via LEFT JOIN on documents → collections.
            // nil means the document is uncategorized (badge is hidden).
            if let collectionName = scoredChunk.collectionName {
                GlassPill {
                    Label(collectionName, systemImage: "folder")
                        .foregroundStyle(.secondary)
                }
            }

            // ── Feedback indicator pills (Task 16.4) ──────────────────────────────
            // Confirms to the user that their signal is being applied to future searches.
            if feedback == .boost {
                GlassPill {
                    Label("Boosted", systemImage: "arrow.up")
                        .foregroundStyle(.green)
                }
            } else if feedback == .hide {
                GlassPill {
                    Text("Hidden")
                        .foregroundStyle(.secondary)
                }
            }

            // ── Relevance / pinned pill ────────────────────────────────────────────
            GlassPill {
                if scoredChunk.isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .foregroundStyle(.orange)
                } else {
                    Text(scoredChunk.relevancePercent)
                        .foregroundStyle(scoreColor)
                }
            }

            // Slide number pill (PDF/PPTX)
            if let slideNumber = chunk.slideNumber {
                GlassPill {
                    Label("Slide \(slideNumber)", systemImage: "rectangle.on.rectangle")
                }
            }

            // Expand / collapse toggle
            GlassIconButton(systemName: "chevron.down", size: 24) {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            }
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    // MARK: - Helpers

    /// Fires the feedback callback and plays a brief spring-pulse on the icon buttons
    /// to give immediate tactile confirmation before the async DB write completes.
    private func applyFeedback(_ type: FeedbackType) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            feedbackScale = 1.3
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5).delay(0.18)) {
            feedbackScale = 1.0
        }
        onFeedback(type)
    }

    /// Maps the relevance score to a traffic-light color: green ≥ 0.7, orange ≥ 0.4, red below.
    private var scoreColor: Color {
        let score = scoredChunk.relevanceScore
        if score >= 0.7 { return .green }
        if score >= 0.4 { return .orange }
        return .red
    }
}
