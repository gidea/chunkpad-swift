import SwiftUI
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

    var body: some View {
        VStack(spacing: 0) {
            ChatMessagesView(viewModel: viewModel) { message in
                await viewModel.saveResponseToKnowledgeBase(message: message)
            }

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
                exportMenu
            }
        }
        .navigationTitle("Chat")
        // Task 13.5: Load collections for scope picker and persist scope changes
        .task {
            previewMinScore = appState.searchMinScore
            panelCollectionId = appState.selectedCollectionId
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
            // Retry button for recoverable network errors
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

    // MARK: - Bottom Bar (Chunks + Search Panel + Input)

    private var bottomBar: some View {
        GlassEffectContainer(spacing: GlassTokens.Spacing.containerFlush) {
            VStack(spacing: 0) {
                // Post-response chunks preview (collapsible)
                if !viewModel.retrievedChunks.isEmpty {
                    ChunksBarView(
                        viewModel: viewModel,
                        isCollapsed: $isChunksBarCollapsed,
                        onRegenerate: regenerate
                    )
                }

                // Pre-send search panel
                if viewModel.isPreviewActive {
                    SearchPanelView(
                        viewModel: viewModel,
                        isExpanded: $isSearchPanelExpanded,
                        previewGrouped: $previewGrouped,
                        previewMinScore: $previewMinScore,
                        panelCollectionId: $panelCollectionId,
                        inputText: inputText,
                        contextSize: appState.contextSize
                    )
                }

                ChatInputBar(
                    inputText: $inputText,
                    viewModel: viewModel,
                    onSend: sendMessage,
                    onSearchPreview: {
                        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !query.isEmpty else { return }
                        Task { await viewModel.searchWithoutSend(query: query) }
                    }
                )
            }
        }
    }

    // MARK: - Generation Mode Picker

    private var generationModePicker: some View {
        @Bindable var appState = appState
        return Picker("Generation", selection: $appState.generationMode) {
            ForEach(GenerationMode.allCases) { mode in
                HStack(spacing: 6) {
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

    // MARK: - Export Menu

    private var exportMenu: some View {
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
                Label("Export as Markdown\u{2026}", systemImage: "square.and.arrow.up")
            }
            Button {
                Task { await exportAsDocx() }
            } label: {
                Label("Export as Word Document\u{2026}", systemImage: "doc.richtext")
            }
            Divider()
            Button {
                Task { await viewModel.saveConversationToKnowledgeBase() }
            } label: {
                Label(viewModel.isSavingToKB ? "Saving\u{2026}" : "Save Conversation to Knowledge Base",
                      systemImage: "tray.and.arrow.down")
            }
            .disabled(viewModel.isSavingToKB)
        } label: {
            if viewModel.isSavingToKB {
                ProgressView().controlSize(.small)
            } else {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        .disabled(viewModel.messages.isEmpty)
    }
}

// MARK: - Actions

private extension ChatView {
    func isProviderConfigured(_ mode: GenerationMode) -> Bool {
        switch mode {
        case .anthropic: return !appState.anthropicAPIKey.isEmpty
        case .openai: return !appState.openaiAPIKey.isEmpty
        case .bundled: return appState.bundledLLMStatus.isReady
        }
    }

    func regenerate() {
        if let provider = appState.resolvedProvider() {
            Task { await viewModel.regenerate(provider: provider) }
        } else if viewModel.isBundledLLMReady {
            let provider = viewModel.makeBundledProvider()
            Task { await viewModel.regenerate(provider: provider) }
        }
    }

    func retryLastMessage() {
        if viewModel.pendingRetryProvider != nil {
            Task { await viewModel.retryLastMessage() }
            return
        }
        if appState.resolvedProvider() != nil {
            Task { await viewModel.retryLastMessage() }
        } else if viewModel.isBundledLLMReady {
            Task { await viewModel.retryLastMessage() }
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // 1. If a cloud or bundled Llama provider is configured, use it directly
        if let provider = appState.resolvedProvider() {
            Task {
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

        // 3. No provider at all — offer Llama download
        Task {
            await viewModel.prepareLlamaOffer(text: text)
        }
    }

    // MARK: - Export

    func copyConversation() {
        MessageExporter.copyConversation(viewModel.messages)
    }

    func exportAsMarkdown() async {
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

    func exportAsDocx() async {
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
}
