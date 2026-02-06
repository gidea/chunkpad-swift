import SwiftUI

/// Orchestrates the full RAG pipeline:
/// 1. Ensure embedding model is downloaded & loaded (lazy, on first search)
/// 2. Embed user query locally via MLX (with BGE query instruction prefix)
/// 3. Hybrid search (sqlite-vec KNN + FTS5)
/// 4. Build context from retrieved chunks
/// 5. Stream response from selected LLM (cloud or local)
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [Message] = []
    var isSearching = false
    var isGenerating = false
    var isDownloadingModel = false
    var retrievedChunks: [Chunk] = []
    var error: String?

    // MARK: - Dependencies

    private let database = DatabaseService()
    private let embedder = EmbeddingService()

    /// Optional reference to the shared AppState for updating global embedding status.
    var appState: AppState?

    // MARK: - Send Message

    func sendMessage(_ text: String, provider: LLMProvider) async {
        guard !text.isEmpty else { return }

        // Add user message
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)
        error = nil

        do {
            // 1. Connect to DB
            try await database.connect()

            // 2. Ensure embedding model is ready (downloads on first use)
            await embedder.setStatusCallback { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState?.embeddingModelStatus = status
                    self.isDownloadingModel = {
                        if case .downloading = status { return true }
                        if case .loading = status { return true }
                        return false
                    }()
                }
            }

            try await embedder.ensureModelReady()
            isDownloadingModel = false

            // 3. Embed the query with BGE query instruction prefix
            isSearching = true
            let queryEmbedding = try await embedder.embedQuery(text)

            // 4. Hybrid search: vector KNN + full-text
            let chunks = try await database.hybridSearch(
                queryEmbedding: queryEmbedding,
                queryText: text,
                k: 10
            )
            retrievedChunks = chunks
            isSearching = false

            // 5. Build context messages for the LLM
            let contextMessages = buildContext(chunks: chunks, query: text)

            // 6. Stream response from selected LLM
            isGenerating = true
            let client = LLMServiceFactory.client(for: provider)

            // Create placeholder assistant message for streaming
            let assistantMessage = Message(
                role: .assistant,
                content: "",
                referencedChunkIDs: chunks.map(\.id)
            )
            messages.append(assistantMessage)
            let assistantIndex = messages.count - 1

            // Stream tokens
            for try await token in client.chatStream(messages: contextMessages) {
                messages[assistantIndex].content += token
            }

            isGenerating = false

            // If the response is empty (stream yielded nothing), try non-streaming fallback
            if messages[assistantIndex].content.isEmpty {
                let fullResponse = try await client.chat(messages: contextMessages)
                messages[assistantIndex].content = fullResponse
            }

        } catch {
            isSearching = false
            isGenerating = false
            isDownloadingModel = false

            if retrievedChunks.isEmpty {
                // Search failed
                self.error = "Search failed: \(error.localizedDescription)"
            } else {
                // LLM call failed — still show retrieved chunks
                self.error = "Generation failed: \(error.localizedDescription)"
                messages.append(Message(
                    role: .assistant,
                    content: "I found \(retrievedChunks.count) relevant chunks but couldn't generate a response. Error: \(error.localizedDescription)",
                    referencedChunkIDs: retrievedChunks.map(\.id)
                ))
            }
        }
    }

    // MARK: - Context Building

    private func buildContext(chunks: [Chunk], query: String) -> [ChatMessage] {
        var contextMessages: [ChatMessage] = []

        // System prompt
        contextMessages.append(ChatMessage(
            role: "system",
            content: """
            You are a helpful assistant that answers questions based on the user's indexed documents. \
            You will be provided with relevant document chunks retrieved from the user's local knowledge base. \
            Always cite which chunks you're referencing in your answer. \
            If the chunks don't contain enough information to answer, say so honestly.
            """
        ))

        // Build the chunk context
        let chunksContext = chunks.enumerated().map { index, chunk in
            """
            [Chunk \(index + 1): \(chunk.id)]
            Source: \(chunk.title)
            \(chunk.slideNumber.map { "Slide \($0)" } ?? "")

            \(chunk.content)
            """
        }.joined(separator: "\n\n---\n\n")

        // User message with context
        contextMessages.append(ChatMessage(
            role: "user",
            content: """
            Here are relevant chunks from my documents:

            \(chunksContext)

            My question: \(query)
            """
        ))

        return contextMessages
    }

    // MARK: - Clear

    func clearConversation() {
        messages.removeAll()
        retrievedChunks.removeAll()
        error = nil
    }
}
