import SwiftUI

/// Detail view showing the chunks for a selected file, with list/grid toggle and filtering.
struct ChunkListView: View {
    let fileInfo: ChunkFileInfo
    let reviewableChunks: [ReviewableChunk]
    var viewMode: DocumentsView.ChunkViewMode
    @Binding var filter: String
    var onToggleInclusion: (String) -> Void
    var onDelete: (ReviewableChunk) -> Void
    var isIndexing: Bool

    var body: some View {
        let filtered = filteredChunks(reviewableChunks)
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter chunks...", text: $filter)
                    .textFieldStyle(.plain)
                if !filter.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
            .padding(.horizontal)
            .padding(.top, 8)

            if filtered.isEmpty && !filter.isEmpty {
                ContentUnavailableView.search(text: filter)
            } else {
                ScrollView {
                    if viewMode == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 12)], spacing: 12) {
                            ForEach(filtered) { rc in
                                ChunkGridCard(
                                    reviewable: rc,
                                    onToggle: { onToggleInclusion(rc.id) },
                                    onDelete: { onDelete(rc) },
                                    isIndexing: isIndexing
                                )
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filtered) { rc in
                                ChunkRowView(
                                    reviewable: rc,
                                    onToggle: { onToggleInclusion(rc.id) },
                                    onDelete: { onDelete(rc) },
                                    isIndexing: isIndexing
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(fileInfo.fileName)
    }

    private func filteredChunks(_ chunks: [ReviewableChunk]) -> [ReviewableChunk] {
        guard !filter.isEmpty else { return chunks }
        let query = filter.lowercased()
        return chunks.filter {
            $0.processedChunk.title.lowercased().contains(query) ||
            $0.processedChunk.content.lowercased().contains(query)
        }
    }
}

// MARK: - Chunk Row (List Mode)

private struct ChunkRowView: View {
    let reviewable: ReviewableChunk
    var onToggle: () -> Void
    var onDelete: () -> Void
    var isIndexing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: reviewable.embeddingStatus.systemImage)
                        .foregroundStyle(reviewable.embeddingStatus.color)
                }
                .buttonStyle(.plain)

                Text(reviewable.processedChunk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()

                if reviewable.isIncluded {
                    ChunkStatusBadge(status: reviewable.embeddingStatus, showLabel: true)
                }

                Text("\(reviewable.processedChunk.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(reviewable.processedChunk.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(20)
        }
        .padding(GlassTokens.Padding.element)
        .opacity(reviewable.isIncluded ? 1 : 0.5)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Chunk", systemImage: "trash")
            }
            .disabled(isIndexing)
        }
    }
}

// MARK: - Chunk Grid Card

private struct ChunkGridCard: View {
    let reviewable: ReviewableChunk
    var onToggle: () -> Void
    var onDelete: () -> Void
    var isIndexing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: onToggle) {
                    Image(systemName: reviewable.embeddingStatus.systemImage)
                        .foregroundStyle(reviewable.embeddingStatus.color)
                }
                .buttonStyle(.plain)

                Text(reviewable.processedChunk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Spacer()
            }

            Text(reviewable.processedChunk.content)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(8)

            HStack {
                if reviewable.isIncluded {
                    ChunkStatusBadge(status: reviewable.embeddingStatus, showLabel: false)
                }
                Spacer()
                Text("\(reviewable.processedChunk.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(GlassTokens.Padding.element)
        .opacity(reviewable.isIncluded ? 1 : 0.5)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Chunk", systemImage: "trash")
            }
            .disabled(isIndexing)
        }
    }
}
