import SwiftUI

/// Collapsible bar showing retrieved chunks after a search, with toggle and regenerate controls.
struct ChunksBarView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isCollapsed: Bool
    var onRegenerate: () -> Void

    var body: some View {
        if isCollapsed {
            collapsedSummary
        } else {
            chunksBar

            // Regenerate button — shown after a response so the user can
            // toggle chunks and re-run generation with the new selection.
            if viewModel.hasChunkSelectionChanged && !viewModel.isGenerating {
                regenerateBar
            }
        }
    }

    // MARK: - Collapsed Summary

    /// Compact summary shown when chunks bar is collapsed.
    private var collapsedSummary: some View {
        let includedCount = viewModel.retrievedChunks.filter(\.isIncluded).count
        let totalCount = viewModel.retrievedChunks.count
        let estimatedTokens = viewModel.retrievedChunks
            .filter(\.isIncluded)
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(includedCount)/\(totalCount) chunks \u{00B7} ~\(estimatedTokens.formatted()) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Chunks Bar

    private var chunksBar: some View {
        VStack(spacing: 0) {
            // Collapse chevron
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed = true
                }
            } label: {
                HStack {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: GlassTokens.Spacing.containerDefault) {
                    HStack(spacing: GlassTokens.Spacing.containerDefault) {
                        ForEach(viewModel.retrievedChunks) { scored in
                            ChunkPreview(scoredChunk: scored) {
                                viewModel.toggleChunk(id: scored.id)
                            } onFeedback: { type in
                                Task { await viewModel.setChunkFeedback(chunkId: scored.id, type: type) }
                            }
                            .frame(width: 260)
                        }

                        // Pin documents button
                        GlassIconButton(systemName: "plus.circle", size: 32) {
                            Task {
                                await viewModel.loadIndexedDocuments()
                                viewModel.showPinDocumentsSheet = true
                            }
                        }
                        .help("Pin documents to always include in context")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 120)
        }
    }

    // MARK: - Regenerate Bar

    private var regenerateBar: some View {
        HStack {
            let includedCount = viewModel.retrievedChunks.filter(\.isIncluded).count
            let totalCount = viewModel.retrievedChunks.count

            Text("\(includedCount)/\(totalCount) chunks selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Show how many chunks were trimmed to fit token budget
            if viewModel.droppedChunkCount > 0 {
                Text("\u{00B7} \(viewModel.droppedChunkCount) trimmed to fit budget")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Feedback signal counts
            let boostedCount = viewModel.retrievedChunks.filter { $0.feedbackType == .boost }.count
            let hiddenCount = viewModel.retrievedChunks.filter { $0.feedbackType == .hide }.count
            if boostedCount > 0 || hiddenCount > 0 {
                let parts = [
                    boostedCount > 0 ? "\(boostedCount) boosted" : nil,
                    hiddenCount > 0 ? "\(hiddenCount) hidden" : nil
                ].compactMap { $0 }
                Text("\u{00B7} " + parts.joined(separator: " \u{00B7} "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onRegenerate) {
                Label("Regenerate", systemImage: "arrow.trianglehead.counterclockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.glass)
            .disabled(viewModel.retrievedChunks.filter(\.isIncluded).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}
