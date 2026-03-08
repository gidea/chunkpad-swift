import SwiftUI
import Combine

/// Scrollable messages area showing the conversation with auto-scroll during streaming.
struct ChatMessagesView: View {
    @Bindable var viewModel: ChatViewModel
    var onSaveToKB: (Message) async -> Void

    /// Timer that fires during streaming to auto-scroll to the bottom.
    private let streamingScrollTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()

    var body: some View {
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
                            MessageBubble(message: message, onSaveToKB: message.role == .assistant ? {
                                Task { await onSaveToKB(message) }
                            } : nil)
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
}
