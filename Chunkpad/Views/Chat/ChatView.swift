import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var isChunksBarCollapsed = false
    // Task 14.2: search panel display state
    @State private var isSearchPanelExpanded = false
    // Task 14.3: flat vs grouped view toggle
    @State private var previewGrouped = false
    // Task 14.4: client-side relevance filter (initialised from appState.searchMinScore in .task)
    @State private var previewMinScore: Double = 0.0
    // Task 14.5: collection scope inside the search panel (independent of global appState scope)
    @State private var panelCollectionId: String? = nil
    /// Timer that fires during streaming to auto-scroll to the bottom.
    private let streamingScrollTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            messagesArea

            if let errorMessage = viewModel.error {
                errorBanner(message: errorMessage, streamingError: viewModel.streamingError) {
                    viewModel.error = nil
                    viewModel.streamingError = nil
                }
            }

            bottomBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    generationModePicker
                    // Task 13.5: Only show scope picker when collections exist
                    if !viewModel.collections.isEmpty {
                        collectionScopePicker
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.createNewConversation() }
                } label: {
                    Label("New Chat", systemImage: "plus.message")
                }
            }
            // Tasks 15.2, 15.3, 15.4: Export menu
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyConversation()
                    } label: {
                        Label("Copy Conversation", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button {
                        Task { await exportAsMarkdown() }
                    } label: {
                        Label("Export as Markdown…", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { await exportAsDocx() }
                    } label: {
                        Label("Export as Word Document…", systemImage: "doc.richtext")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.messages.isEmpty)
            }
        }
        .navigationTitle("Chat")
        // Task 13.5: Load collections for scope picker and persist scope changes
        .task {
            previewMinScore = appState.searchMinScore   // 14.4: init slider from settings
            panelCollectionId = appState.selectedCollectionId  // 14.5: align panel scope with global scope
            await viewModel.refreshCollections()
        }
        .onChange(of: appState.selectedCollectionId) {
            appState.saveToUserProfile()
        }
        .onChange(of: viewModel.isPreviewActive) { _, active in
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchPanelExpanded = active
            }
        }
        // Llama download offer dialog
        .alert("No LLM Provider Configured", isPresented: $viewModel.showLlamaOffer) {
            Button("Download Llama") {
                Task {
                    await viewModel.downloadLlamaAndSend()
                }
            }
            Button("Open Settings") {
                appState.selectedItem = .settings
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No API key is configured for Claude or ChatGPT.\n\nWould you like to download Llama 3.2 (\(BundledLLMService.modelSize)) for free local generation on your Mac?")
        }
        // Pin documents sheet
        .sheet(isPresented: $viewModel.showPinDocumentsSheet) {
            PinDocumentsSheet(
                documents: viewModel.indexedDocuments,
                pinnedIDs: viewModel.pinnedDocumentIDs,
                onToggle: { id in viewModel.togglePinDocument(id: id) }
            )
        }
    }

    // MARK: - Error Banner

    private func errorBanner(
        message: String,
        streamingError: StreamingErrorKind?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            // 6.4: Retry button for recoverable network errors
            if let kind = streamingError, kind.canRetryNow {
                Button("Retry") {
                    onDismiss()
                    retryLastMessage()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Button("Dismiss", role: .cancel, action: onDismiss)
                .buttonStyle(.borderless)
                .font(.caption.weight(.medium))
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Messages Area

    @ViewBuilder
    private var messagesArea: some View {
        if viewModel.messages.isEmpty {
            ContentUnavailableView {
                Label("Start a Conversation", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Ask questions about your indexed documents.\nChunkpad searches locally via MLX + sqlite-vec, then generates answers with your chosen LLM.")
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Llama download progress
                        if viewModel.isDownloadingLlama {
                            HStack(spacing: 8) {
                                ProgressView(value: viewModel.llamaDownloadProgress)
                                    .frame(width: 120)
                                Text("Downloading Llama 3.2... \(Int(viewModel.llamaDownloadProgress * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }

                        if viewModel.isSearching {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching documents...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }

                        if viewModel.isGenerating {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating response...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }

                        // Invisible anchor at bottom for scroll-to-end
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.isGenerating) { _, generating in
                    if generating {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onReceive(streamingScrollTimer) { _ in
                    guard viewModel.isGenerating else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Bottom Bar (Chunks + Input)

    private var bottomBar: some View {
        GlassEffectContainer(spacing: GlassTokens.Spacing.containerFlush) {
            VStack(spacing: 0) {
                // Post-response chunks preview (collapsible) — shown after a message is sent
                if !viewModel.retrievedChunks.isEmpty {
                    if isChunksBarCollapsed {
                        collapsedChunksSummary
                    } else {
                        chunksBar

                        // Regenerate button — shown after a response so the user can
                        // toggle chunks and re-run generation with the new selection.
                        if viewModel.hasChunkSelectionChanged && !viewModel.isGenerating {
                            regenerateBar
                        }
                    }
                }

                // Task 14.2: Pre-send search panel — shown when preview chunks are loaded
                if viewModel.isPreviewActive {
                    searchPanel
                }

                inputBar
            }
        }
    }

    // MARK: - Chunks Bar

    /// 7.3: Compact summary shown when chunks bar is collapsed.
    private var collapsedChunksSummary: some View {
        let includedCount = viewModel.retrievedChunks.filter(\.isIncluded).count
        let totalCount = viewModel.retrievedChunks.count
        let estimatedTokens = viewModel.retrievedChunks
            .filter(\.isIncluded)
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isChunksBarCollapsed = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(includedCount)/\(totalCount) chunks · ~\(estimatedTokens.formatted()) tokens")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var chunksBar: some View {
        VStack(spacing: 0) {
            // Collapse chevron
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isChunksBarCollapsed = true
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

                        // Pin documents button — opens sheet to manually include documents
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

            // 9.1: Show how many chunks were trimmed to fit token budget
            if viewModel.droppedChunkCount > 0 {
                Text("· \(viewModel.droppedChunkCount) trimmed to fit budget")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Task 16.4: Feedback signal counts — confirms signals are active
            let boostedCount = viewModel.retrievedChunks.filter { $0.feedbackType == .boost }.count
            let hiddenCount = viewModel.retrievedChunks.filter { $0.feedbackType == .hide }.count
            if boostedCount > 0 || hiddenCount > 0 {
                let parts = [
                    boostedCount > 0 ? "\(boostedCount) boosted" : nil,
                    hiddenCount > 0 ? "\(hiddenCount) hidden" : nil
                ].compactMap { $0 }
                Text("· " + parts.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                regenerate()
            } label: {
                Label("Regenerate", systemImage: "arrow.trianglehead.counterclockwise")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.glass)
            .disabled(viewModel.retrievedChunks.filter(\.isIncluded).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            // 7.4: Always-visible pin button for pre-query document pinning
            pinButton

            // Task 14.1: Search-before-send button
            searchPreviewButton

            TextField("Ask about your documents...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { sendMessage() }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.input))

            Button {
                if viewModel.isGenerating {
                    viewModel.cancelGeneration()
                } else {
                    sendMessage()
                }
            } label: {
                if viewModel.isPreviewActive && !viewModel.isGenerating {
                    // Task 14.1: Show chunk count on send button when preview is loaded
                    Label("Send · \(viewModel.previewIncludedCount)", systemImage: "arrow.up.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 36)
                } else {
                    Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 36, height: 36)
                }
            }
            .buttonStyle(.glass)
            .disabled(!viewModel.isGenerating && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command) // Cmd+Return as backup
            .help(viewModel.isGenerating ? "Stop generation" : "Send")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.card))
        // 80% width with 10% margins on each side
        .containerRelativeFrame(.horizontal) { length, _ in
            length * 0.8
        }
        .padding(.bottom, 12)
    }

    // MARK: - Pin Button

    /// 7.4: Always-visible pin button with badge showing pinned document count.
    private var pinButton: some View {
        let pinnedCount = viewModel.pinnedDocumentIDs.count

        return Button {
            Task {
                await viewModel.loadIndexedDocuments()
                viewModel.showPinDocumentsSheet = true
            }
        } label: {
            Image(systemName: pinnedCount > 0 ? "pin.fill" : "pin")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)
                .overlay(alignment: .topTrailing) {
                    if pinnedCount > 0 {
                        Text("\(pinnedCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(.orange, in: .circle)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.glass)
        .help(pinnedCount > 0 ? "\(pinnedCount) pinned document\(pinnedCount == 1 ? "" : "s")" : "Pin documents to always include in context")
    }

    // MARK: - Generation Mode Picker

    private var generationModePicker: some View {
        @Bindable var appState = appState
        return Picker("Generation", selection: $appState.generationMode) {
            ForEach(GenerationMode.allCases) { mode in
                HStack(spacing: 6) {
                    // 7.5: Colored dot — green if configured, gray if not
                    Circle()
                        .fill(isProviderConfigured(mode) ? .green : .gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Label(mode.displayName, systemImage: mode.icon)
                }
                .tag(mode)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
    }

    // MARK: - Collection Scope Picker (Task 13.5)

    /// Lets the user scope hybrid search to a single collection or all documents.
    /// Hidden when no collections exist (no clutter for users who don't use collections).
    private var collectionScopePicker: some View {
        @Bindable var appState = appState
        return Picker("Scope", selection: $appState.selectedCollectionId) {
            Label("All Documents", systemImage: "tray.2")
                .tag(Optional<String>.none)
            Divider()
            ForEach(viewModel.collections) { collection in
                Label(collection.name, systemImage: "folder.fill")
                    .tag(Optional(collection.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 180)
        .help(appState.selectedCollectionId == nil
              ? "Search scope: All Documents"
              : "Search scope: \(viewModel.collections.first { $0.id == appState.selectedCollectionId }?.name ?? "Collection")")
    }

    /// 7.5: Check if a generation mode has a valid configuration.
    private func isProviderConfigured(_ mode: GenerationMode) -> Bool {
        switch mode {
        case .anthropic: return !appState.anthropicAPIKey.isEmpty
        case .openai: return !appState.openaiAPIKey.isEmpty
        case .bundled: return appState.bundledLLMStatus.isReady
        }
    }

    // MARK: - Search Preview Button (Task 14.1)

    /// Magnifyingglass button in the input bar that triggers search-before-send.
    private var searchPreviewButton: some View {
        Button {
            let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            Task { await viewModel.searchWithoutSend(query: query) }
        } label: {
            ZStack {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .frame(width: 32, height: 32)
                    .opacity(viewModel.isSearchingPreview ? 0 : 1)
                if viewModel.isSearchingPreview {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.glass)
        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  || viewModel.isSearchingPreview
                  || viewModel.isGenerating)
        .help("Preview which chunks will be retrieved without sending")
        .keyboardShortcut("k", modifiers: .command)
    }

    // MARK: - Search Panel (Tasks 14.2, 14.3, 14.4)

    /// Collapsible panel showing pre-send search results with inline controls.
    private var searchPanel: some View {
        VStack(spacing: 0) {
            searchPanelHeader

            if isSearchPanelExpanded {
                Divider()
                    .opacity(0.3)

                // Task 14.4: relevance slider + re-search button
                relevanceControls

                // Token budget progress bar
                tokenBudgetBar

                // Task 14.3: flat or grouped chunk list
                if previewGrouped {
                    groupedChunkList
                } else {
                    flatPreviewList
                }
            }
        }
    }

    /// Header row: collapse chevron, summary text, flat/group toggle, dismiss button.
    private var searchPanelHeader: some View {
        let visible = viewModel.previewChunks.filter { $0.relevanceScore >= previewMinScore }
        let includedCount = visible.filter(\.isIncluded).count
        let totalTokens = visible.filter(\.isIncluded)
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }
        let docCount = Set(visible.map(\.chunk.sourcePath)).count

        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchPanelExpanded.toggle()
                }
            } label: {
                Image(systemName: isSearchPanelExpanded ? "chevron.down" : "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(docCount) doc\(docCount == 1 ? "" : "s") · \(includedCount)/\(visible.count) chunks · ~\(totalTokens.formatted()) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Task 14.3: segmented flat/grouped toggle
            Picker("View", selection: $previewGrouped) {
                Image(systemName: "list.bullet").tag(false)
                Image(systemName: "square.stack").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 64)
            .controlSize(.mini)

            // Task 14.5: inline collection scope picker for the search panel
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

    /// Task 14.4: Min-relevance slider + Re-search button.
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

    /// Colour-coded token budget bar (green < 75%, orange < 90%, red >= 90%).
    private var tokenBudgetBar: some View {
        let budget = Int(Double(appState.contextSize) * 0.8)
        let used = viewModel.previewChunks
            .filter { $0.isIncluded && $0.relevanceScore >= previewMinScore }
            .reduce(0) { $0 + max(1, $1.chunk.content.count / 4) }
        let fraction = min(1.0, Double(used) / Double(max(1, budget)))
        let barColor: Color = fraction < 0.75 ? .green : fraction < 0.9 ? .orange : .red

        return HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08)).frame(height: 4)
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(4, geo.size.width * fraction), height: 4)
                }
            }
            .frame(height: 4)

            Text("\(used.formatted())/\(budget.formatted()) tok")
                .font(.caption2)
                .foregroundStyle(fraction < 0.75 ? AnyShapeStyle(.secondary) : fraction < 0.9 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.red))
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

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

    /// Task 14.3: Vertical scroll of document-level groups, each with a horizontal chunk row.
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

    /// One document header + horizontal chunk strip, with a "Remove" button (14.3).
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
                Text("· \(includedCount)/\(chunks.count) · ~\(totalTokens.formatted()) tok")
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

    // MARK: - Actions

    private func regenerate() {
        // Resolve provider the same way sendMessage does
        if let provider = appState.resolvedProvider() {
            Task { await viewModel.regenerate(provider: provider) }
        } else if viewModel.isBundledLLMReady {
            let provider = viewModel.makeBundledProvider()
            Task { await viewModel.regenerate(provider: provider) }
        }
    }

    /// 6.4: Retry the last message after a network error (uses stored provider + existing chunks).
    private func retryLastMessage() {
        if viewModel.pendingRetryProvider != nil {
            Task { await viewModel.retryLastMessage() }
            return
        }
        // Fallback: resolve provider fresh
        if appState.resolvedProvider() != nil {
            Task { await viewModel.retryLastMessage() }
        } else if viewModel.isBundledLLMReady {
            Task { await viewModel.retryLastMessage() }
        }
    }

    // MARK: - Export

    private func copyConversation() {
        MessageExporter.copyConversation(viewModel.messages)
    }

    private func exportAsMarkdown() async {
        let content = viewModel.exportAsMarkdown()
        let filename = viewModel.exportFilename(extension: "md")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) == .OK,
              let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            // swallow — user can retry
        }
    }

    private func exportAsDocx() async {
        let filename = viewModel.exportFilename(extension: "docx")
        do {
            let tempURL = try await viewModel.exportAsDocx()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = filename
            panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
            panel.canCreateDirectories = true
            guard await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow()) == .OK,
                  let dest = panel.url else {
                try? FileManager.default.removeItem(at: tempURL)
                return
            }
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
        } catch {
            // swallow — user can retry
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // 1. If a cloud or bundled Llama provider is configured, use it directly
        if let provider = appState.resolvedProvider() {
            Task {
                // Task 14.1: use preview chunks if the search panel is loaded
                if viewModel.isPreviewActive {
                    await viewModel.sendWithPreview(text, provider: provider)
                } else {
                    await viewModel.sendMessage(text, provider: provider)
                }
            }
            return
        }

        // 2. If bundled Llama is already downloaded, use it
        if viewModel.isBundledLLMReady {
            let provider = viewModel.makeBundledProvider()
            Task {
                if viewModel.isPreviewActive {
                    await viewModel.sendWithPreview(text, provider: provider)
                } else {
                    await viewModel.sendMessage(text, provider: provider)
                }
            }
            return
        }

        // 3. No provider at all — create conversation if needed, add user message, persist, then offer Llama download
        Task {
            await viewModel.prepareLlamaOffer(text: text)
        }
    }
}
