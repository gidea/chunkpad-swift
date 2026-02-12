import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ChatViewModel
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            messagesArea

            if let errorMessage = viewModel.error {
                errorBanner(message: errorMessage) {
                    viewModel.error = nil
                }
            }

            bottomBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                generationModePicker
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.createNewConversation() }
                } label: {
                    Label("New Chat", systemImage: "plus.message")
                }
            }
        }
        .navigationTitle("Chat")
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

    private func errorBanner(message: String, onDismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
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
            }
        }
    }

    // MARK: - Bottom Bar (Chunks + Input)

    private var bottomBar: some View {
        GlassEffectContainer(spacing: GlassTokens.Spacing.containerFlush) {
            VStack(spacing: 0) {
                // Retrieved chunks preview (collapsible)
                if !viewModel.retrievedChunks.isEmpty {
                    chunksBar

                    // Regenerate button — shown after a response so the user can
                    // toggle chunks and re-run generation with the new selection.
                    if viewModel.hasChunkSelectionChanged && !viewModel.isGenerating {
                        regenerateBar
                    }
                }

                inputBar
            }
        }
    }

    // MARK: - Chunks Bar

    private var chunksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: GlassTokens.Spacing.containerDefault) {
                HStack(spacing: GlassTokens.Spacing.containerDefault) {
                    ForEach(viewModel.retrievedChunks) { scored in
                        ChunkPreview(scoredChunk: scored) {
                            viewModel.toggleChunk(id: scored.id)
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

    // MARK: - Regenerate Bar

    private var regenerateBar: some View {
        HStack {
            let includedCount = viewModel.retrievedChunks.filter(\.isIncluded).count
            let totalCount = viewModel.retrievedChunks.count

            Text("\(includedCount)/\(totalCount) chunks selected")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36, height: 36)
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

    // MARK: - Generation Mode Picker

    private var generationModePicker: some View {
        @Bindable var appState = appState
        return Picker("Generation", selection: $appState.generationMode) {
            ForEach(GenerationMode.allCases) { mode in
                Label(mode.displayName, systemImage: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 200)
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

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // 1. If a cloud/Ollama provider is configured, use it directly
        if let provider = appState.resolvedProvider() {
            Task {
                await viewModel.sendMessage(text, provider: provider)
            }
            return
        }

        // 2. If bundled Llama is already downloaded, use it
        if viewModel.isBundledLLMReady {
            let provider = viewModel.makeBundledProvider()
            Task {
                await viewModel.sendMessage(text, provider: provider)
            }
            return
        }

        // 3. No provider at all — create conversation if needed, add user message, persist, then offer Llama download
        Task {
            await viewModel.prepareLlamaOffer(text: text)
        }
    }
}
