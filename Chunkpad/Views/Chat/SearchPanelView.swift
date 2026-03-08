import SwiftUI

/// Collapsible panel showing pre-send search results with inline controls.
struct SearchPanelView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var isExpanded: Bool
    @Binding var previewGrouped: Bool
    @Binding var previewMinScore: Double
    @Binding var panelCollectionId: String?
    var inputText: String
    var contextSize: Int

    var body: some View {
        VStack(spacing: 0) {
            header

            if isExpanded {
                Divider()
                    .opacity(0.3)

                relevanceControls
                tokenBudgetBar

                if previewGrouped {
                    groupedChunkList
                } else {
                    flatPreviewList
                }
            }
        }
    }

    // MARK: - Header

    /// Header row: collapse chevron, summary text, flat/group toggle, dismiss button.
    private var header: some View {
        let visible = viewModel.previewChunks.filter { $0.relevanceScore >= previewMinScore }
        let includedCount = visible.filter(\.isIncluded).count
        let totalTokens = visible.filter(\.isIncluded)
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }
        let docCount = Set(visible.map(\.chunk.sourcePath)).count

        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(docCount) doc\(docCount == 1 ? "" : "s") \u{00B7} \(includedCount)/\(visible.count) chunks \u{00B7} ~\(totalTokens.formatted()) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Segmented flat/grouped toggle
            Picker("View", selection: $previewGrouped) {
                Image(systemName: "list.bullet").tag(false)
                Image(systemName: "square.stack").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 64)
            .controlSize(.mini)

            // Inline collection scope picker for the search panel
            Picker("Scope", selection: $panelCollectionId) {
                Text("All Documents").tag(String?.none)
                ForEach(viewModel.collections) { col in
                    Text(col.name).tag(Optional(col.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: panelCollectionId) { _, _ in
                // Re-run search when scope changes (only if there's an active query)
                let q = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty {
                    Task { await viewModel.searchWithoutSend(query: q, collectionId: panelCollectionId) }
                }
            }

            // Dismiss the preview panel
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.clearPreview()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Clear search preview")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Relevance Controls

    /// Min-relevance slider + Re-search button.
    private var relevanceControls: some View {
        HStack(spacing: 10) {
            Text("Min relevance: \(previewMinScore, specifier: "%.2f")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            Slider(value: $previewMinScore, in: 0.0...1.0, step: 0.05)

            Button("Re-search") {
                let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty else { return }
                Task { await viewModel.searchWithoutSend(query: query, collectionId: panelCollectionId) }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .font(.caption.weight(.medium))
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || viewModel.isSearchingPreview)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Token Budget Bar

    /// Colour-coded token budget bar with exact counts, percentage, and over-budget warning.
    private var tokenBudgetBar: some View {
        let budget = Int(Double(contextSize) * 0.8)
        let used = viewModel.previewChunks
            .filter { $0.isIncluded && $0.relevanceScore >= previewMinScore }
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }
        let fraction = min(1.0, Double(used) / Double(max(1, budget)))
        let barColor: Color = fraction < 0.5 ? .green : fraction < 0.8 ? .orange : .red

        return VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("~\(used.formatted()) / \(budget.formatted()) tokens (\(Int(fraction * 100))% of budget)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if fraction > 0.8 {
                    Text("Some chunks may be trimmed on send")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    // MARK: - Flat Preview List

    /// Flat horizontal scroll of ChunkPreview cards, filtered by relevance slider.
    private var flatPreviewList: some View {
        let visible = viewModel.previewChunks.filter { $0.relevanceScore >= previewMinScore }
        return ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: GlassTokens.Spacing.containerDefault) {
                HStack(spacing: GlassTokens.Spacing.containerDefault) {
                    ForEach(visible) { scored in
                        ChunkPreview(scoredChunk: scored) {
                            viewModel.togglePreviewChunk(id: scored.id)
                        } onFeedback: { type in
                            Task { await viewModel.setChunkFeedback(chunkId: scored.id, type: type) }
                        }
                        .frame(width: 260)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Grouped Chunk List

    /// Vertical scroll of document-level groups, each with a horizontal chunk row.
    private var groupedChunkList: some View {
        let visible = viewModel.previewChunks.filter { $0.relevanceScore >= previewMinScore }
        let groups = Dictionary(grouping: visible, by: \.chunk.sourcePath)
        let sortedPaths = groups.keys.sorted()

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(sortedPaths, id: \.self) { path in
                    if let chunks = groups[path] {
                        documentGroupRow(sourcePath: path, chunks: chunks)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 200)
    }

    /// One document header + horizontal chunk strip, with a "Remove" button.
    private func documentGroupRow(sourcePath: String, chunks: [ScoredChunk]) -> some View {
        let includedCount = chunks.filter(\.isIncluded).count
        let totalTokens = chunks.filter(\.isIncluded)
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }
        let fileName = URL(fileURLWithPath: sourcePath).lastPathComponent

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\u{00B7} \(includedCount)/\(chunks.count) \u{00B7} ~\(totalTokens.formatted()) tok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    viewModel.removePreviewDocument(sourcePath: sourcePath)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .font(.caption)
            }
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GlassTokens.Spacing.containerDefault) {
                    ForEach(chunks) { scored in
                        ChunkPreview(scoredChunk: scored) {
                            viewModel.togglePreviewChunk(id: scored.id)
                        } onFeedback: { type in
                            Task { await viewModel.setChunkFeedback(chunkId: scored.id, type: type) }
                        }
                        .frame(width: 240)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.card))
    }
}
