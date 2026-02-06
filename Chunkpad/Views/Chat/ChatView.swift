import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            messagesArea

            // Retrieved chunks preview (collapsible)
            if !viewModel.retrievedChunks.isEmpty {
                chunksBar
            }

            Divider()

            inputBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                generationModePicker
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label("New Chat", systemImage: "plus.message")
                }
                .disabled(viewModel.messages.isEmpty)
            }
        }
        .navigationTitle("Chat")
        .onAppear {
            viewModel.appState = appState
        }
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
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                    }

                    if viewModel.isDownloadingModel {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading embedding model (first-time setup)...")
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
                }
                .padding()
            }
        }
    }

    // MARK: - Chunks Bar

    private var chunksBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.retrievedChunks) { chunk in
                    ChunkPreview(chunk: chunk)
                        .frame(width: 260)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 120)
        .background(.ultraThinMaterial)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your documents...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isGenerating)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
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

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        guard let provider = appState.resolvedProvider() else {
            viewModel.messages.append(Message(
                role: .assistant,
                content: "Please configure your LLM provider in Settings. Cloud providers need an API key; local providers need Ollama running."
            ))
            return
        }

        Task {
            await viewModel.sendMessage(text, provider: provider)
        }
    }
}
