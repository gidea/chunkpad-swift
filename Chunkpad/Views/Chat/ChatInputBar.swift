import SwiftUI

/// Input bar at the bottom of the chat, with text field, pin button, search preview, and send.
struct ChatInputBar: View {
    @Binding var inputText: String
    @Bindable var viewModel: ChatViewModel
    var onSend: () -> Void
    var onSearchPreview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Always-visible pin button for pre-query document pinning
            pinButton

            // Search-before-send button
            searchPreviewButton

            TextField("Ask about your documents...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit { onSend() }
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.input))

            Button {
                if viewModel.isGenerating {
                    viewModel.cancelGeneration()
                } else {
                    onSend()
                }
            } label: {
                if viewModel.isPreviewActive && !viewModel.isGenerating {
                    // Show chunk count on send button when preview is loaded
                    Label("Send \u{00B7} \(viewModel.previewIncludedCount)", systemImage: "arrow.up.circle.fill")
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
            .keyboardShortcut(.return, modifiers: .command)
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

    /// Always-visible pin button with badge showing pinned document count.
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

    // MARK: - Search Preview Button

    /// Magnifyingglass button that triggers search-before-send.
    private var searchPreviewButton: some View {
        Button(action: onSearchPreview) {
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
}
