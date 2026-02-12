import SwiftUI

/// A persisted chat conversation (metadata only; messages are stored separately).
/// Declared here so the @Observable macro expansion can resolve the type.
struct Conversation: Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
}

/// Orchestrates the full RAG pipeline:
/// 1. Verify documents are indexed (embedding model was downloaded during indexing)
/// 2. Load embedding model from local cache (NEVER triggers a download)
/// 3. Embed user query locally via MLX (with BGE query instruction prefix)
/// 4. Hybrid search (sqlite-vec KNN + FTS5)
/// 5. Build context from retrieved chunks
/// 6. Stream response from selected LLM (cloud, Ollama, or bundled Llama)
///
/// Model download rules:
/// - Embedding model (bge-base-en-v1.5): downloaded ONLY during document indexing, never here.
/// - Llama 3.2: downloaded ONLY when user explicitly accepts the offer (no cloud API key).
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [Message] = []
    var isSearching = false
    var isGenerating = false
    var isDownloadingModel = false
    var retrievedChunks: [ScoredChunk] = []
    var error: String?

    /// Current conversation id (nil = no conversation selected; new conversation created on first send).
    var currentConversationId: String?

    /// List of past conversations for the sidebar. Refresh via refreshConversations().
    var conversations: [Conversation] = []

    // MARK: - Llama Offer State

    /// When true, the chat view shows an alert offering to download Llama 3.2.
    var showLlamaOffer = false

    /// The message text to retry after Llama finishes downloading.
    var pendingMessage: String?

    /// True while Llama 3.2 is being downloaded from HuggingFace.
    var isDownloadingLlama = false

    /// Download progress for Llama (0.0 to 1.0).
    var llamaDownloadProgress: Double = 0

    /// True after Llama 3.2 has been downloaded and loaded (from AppState, so Settings download is reflected).
    var isBundledLLMReady: Bool { appState?.bundledLLMStatus.isReady ?? false }

    // MARK: - Pin Documents State

    /// When true, the pin-documents sheet is presented.
    var showPinDocumentsSheet = false

    /// All indexed documents (fetched when the pin sheet opens).
    var indexedDocuments: [IndexedDocument] = []

    /// IDs of documents the user has pinned. Pinned documents' chunks
    /// are always included at the top of search results.
    var pinnedDocumentIDs: Set<String> = []

    // MARK: - Dependencies

    private let database = DatabaseService()
    private let embedder = EmbeddingService()

    /// Optional reference to the shared AppState for reading global state and conversation DB.
    var appState: AppState?

    private var conversationDB: ConversationDatabaseService? { appState?.conversationDatabase }

    /// Current generation task; cancelled when the user taps Stop.
    private var generationTask: Task<Void, Never>?

    // MARK: - Conversation Lifecycle

    /// Creates a new conversation in the chat DB, sets it as current, and clears local state.
    /// Call and await before sending the first message when currentConversationId == nil.
    func createNewConversation() async {
        guard let conversationDB else { return }
        do {
            let id = try await conversationDB.createConversation(title: "New Chat")
            currentConversationId = id
            messages.removeAll()
            retrievedChunks.removeAll()
            error = nil
            await refreshConversations()
        } catch {
            self.error = "Failed to create conversation: \(error.localizedDescription)"
        }
    }

    /// Loads a conversation from the chat DB into messages and sets it as current.
    func loadConversation(id: String) async {
        guard let conversationDB else { return }
        do {
            let msgs = try await conversationDB.fetchMessages(conversationId: id)
            currentConversationId = id
            messages = msgs
            retrievedChunks.removeAll()
            error = nil
        } catch {
            self.error = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    /// Refreshes the conversation list from the chat DB (e.g. after creating or adding messages).
    func refreshConversations() async {
        guard let conversationDB else { return }
        do {
            let list = try await conversationDB.fetchConversations(limit: 100)
            await MainActor.run { conversations = list }
        } catch {
            // Non-fatal; list stays as-is
        }
    }

    // MARK: - Send Message

    /// Run the full RAG pipeline: embed → search → generate.
    ///
    /// - Parameters:
    ///   - text: The user's query.
    ///   - provider: The resolved LLM provider (cloud, local, or bundled).
    ///   - userMessageAlreadyAdded: If true, skip adding the user message (already shown in chat).
    func sendMessage(_ text: String, provider: LLMProvider, userMessageAlreadyAdded: Bool = false) async {
        guard !text.isEmpty else { return }

        if currentConversationId == nil {
            await createNewConversation()
            guard currentConversationId != nil else { return }
        }

        if !userMessageAlreadyAdded {
            let userMessage = Message(role: .user, content: text)
            messages.append(userMessage)
            if let cid = currentConversationId, let conversationDB {
                try? await conversationDB.insertMessage(userMessage, conversationId: cid)
                if messages.count == 1, let convId = currentConversationId {
                    let title = String(text.prefix(50))
                    let trimmed = title.count < text.count ? title + "…" : title
                    try? await conversationDB.updateConversation(id: convId, title: trimmed, updatedAt: Date())
                }
                await refreshConversations()
            }
        }
        error = nil

        do {
            // 1. Connect to DB
            try await database.connect()

            // 2. Check that documents have been indexed.
            //    The embedding model is ONLY downloaded during document indexing — never here.
            //    If no documents are indexed, there is nothing to search and the embedding
            //    model may not be cached locally yet.
            guard (appState?.indexedDocumentCount ?? 0) > 0 else {
                self.error = "No documents indexed yet. Go to Documents and index a folder first."
                return
            }

            // 3. Load embedding model from local cache (was downloaded during indexing).
            //    This calls ensureModelReady() which loads cached weights into memory.
            //    If the model was cached during indexing, this is instant.
            //    This does NOT trigger a new download — the indexedDocumentCount check above
            //    ensures the model was previously downloaded.
            try await embedder.ensureModelReady()

            // 4. Embed the query with BGE query instruction prefix
            isSearching = true
            let queryEmbedding = try await embedder.embedQuery(text)

            // 5. Hybrid search: vector KNN + full-text (with min-score threshold)
            var scoredChunks = try await database.hybridSearch(
                queryEmbedding: queryEmbedding,
                queryText: text,
                k: 10,
                minScore: 0.1
            )

            // 5b. Merge pinned document chunks (boosted to score 1.0)
            try await addPinnedChunks(to: &scoredChunks)

            retrievedChunks = scoredChunks
            isSearching = false

            // 6. Build context messages for the LLM (only included chunks)
            let contextMessages = buildContext(scoredChunks: scoredChunks, query: text)

            // 7. Stream response from selected LLM (cloud, Ollama, or bundled Llama)
            let client = LLMServiceFactory.client(for: provider)
            let includedChunks = scoredChunks.filter(\.isIncluded)
            let assistantMessage = Message(
                role: .assistant,
                content: "",
                referencedChunkIDs: includedChunks.map(\.id)
            )
            messages.append(assistantMessage)
            let assistantIndex = messages.count - 1

            generationTask = Task {
                isGenerating = true
                defer {
                    generationTask = nil
                    isGenerating = false
                }
                do {
                    for try await token in client.chatStream(messages: contextMessages) {
                        if Task.isCancelled { break }
                        messages[assistantIndex].content += token
                    }
                    if messages[assistantIndex].content.isEmpty && !Task.isCancelled {
                        let fullResponse = try await client.chat(messages: contextMessages)
                        messages[assistantIndex].content = fullResponse
                    }
                    if Task.isCancelled && !messages[assistantIndex].content.isEmpty {
                        messages[assistantIndex].content += "\n\n(Stopped)"
                    }
                    if let cid = currentConversationId, let conversationDB {
                        try? await conversationDB.insertMessage(messages[assistantIndex], conversationId: cid)
                        await refreshConversations()
                    }
                } catch is CancellationError {
                    if !messages[assistantIndex].content.isEmpty {
                        messages[assistantIndex].content += "\n\n(Stopped)"
                    }
                    if let cid = currentConversationId, let conversationDB {
                        try? await conversationDB.insertMessage(messages[assistantIndex], conversationId: cid)
                        await refreshConversations()
                    }
                } catch {
                    self.error = "Generation failed: \(error.localizedDescription)"
                }
            }
            await generationTask?.value

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
                let errMessage = Message(
                    role: .assistant,
                    content: "I found \(retrievedChunks.count) relevant chunks but couldn't generate a response. Error: \(error.localizedDescription)",
                    referencedChunkIDs: retrievedChunks.map(\.id)
                )
                messages.append(errMessage)
                if let cid = currentConversationId, let conversationDB {
                    try? await conversationDB.insertMessage(errMessage, conversationId: cid)
                    await refreshConversations()
                }
            }
        }
    }

    // MARK: - Llama Offer (No API Key)

    /// When no provider is configured, create conversation, persist the user message, then show Llama download offer.
    /// So when the user accepts, sendMessage(..., userMessageAlreadyAdded: true) has a valid conversation and message.
    func prepareLlamaOffer(text: String) async {
        if currentConversationId == nil {
            await createNewConversation()
            guard currentConversationId != nil else { return }
        }
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)
        if let cid = currentConversationId, let conversationDB {
            try? await conversationDB.insertMessage(userMessage, conversationId: cid)
            if messages.count == 1 {
                let title = String(text.prefix(50))
                let trimmed = title.count < text.count ? title + "…" : title
                try? await conversationDB.updateConversation(id: cid, title: trimmed, updatedAt: Date())
            }
            await refreshConversations()
        }
        pendingMessage = text
        showLlamaOffer = true
    }

    // MARK: - Llama Download & Retry

    /// Downloads Llama 3.2 from HuggingFace, then sends the pending message with the bundled provider.
    /// Called after the user accepts the Llama offer dialog.
    func downloadLlamaAndSend() async {
        guard let text = pendingMessage else { return }

        showLlamaOffer = false
        isDownloadingLlama = true
        llamaDownloadProgress = 0

        let llm = BundledLLMService.shared
        await llm.setStatusCallback { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading(let p) = status {
                    self.llamaDownloadProgress = p
                }
            }
        }

        do {
            try await llm.downloadAndLoad()
            isDownloadingLlama = false
            // appState.bundledLLMStatus is updated via callback → isBundledLLMReady becomes true

            // Send the pending message with the bundled provider (user message already shown)
            let provider = LLMProvider.local(LocalConfig(provider: .bundled))
            await sendMessage(text, provider: provider, userMessageAlreadyAdded: true)
            pendingMessage = nil
        } catch {
            isDownloadingLlama = false
            self.error = "Failed to download Llama: \(error.localizedDescription)"
        }
    }

    /// Build an LLMProvider for the bundled Llama model.
    func makeBundledProvider() -> LLMProvider {
        .local(LocalConfig(provider: .bundled))
    }

    // MARK: - Pin Documents

    /// Loads the list of indexed documents for the pin sheet.
    func loadIndexedDocuments() async {
        do {
            try await database.connect()
            let docs = try await database.listDocuments()
            indexedDocuments = docs
        } catch {
            self.error = "Failed to load documents: \(error.localizedDescription)"
        }
    }

    /// Toggle whether a document is pinned. Pinned documents' chunks are
    /// always boosted in the next search.
    func togglePinDocument(id: String) {
        if pinnedDocumentIDs.contains(id) {
            pinnedDocumentIDs.remove(id)
        } else {
            pinnedDocumentIDs.insert(id)
        }
    }

    /// Fetches chunks for all pinned documents and merges them into the
    /// current `retrievedChunks` with a high relevance score (1.0),
    /// avoiding duplicates.
    private func addPinnedChunks(to scoredChunks: inout [ScoredChunk]) async throws {
        guard !pinnedDocumentIDs.isEmpty else { return }

        let existingIDs = Set(scoredChunks.map(\.id))
        for docID in pinnedDocumentIDs {
            let chunks = try await database.chunksForDocument(documentID: docID)
            for chunk in chunks where !existingIDs.contains(chunk.id) {
                // Pinned chunks get a score of 1.0 so they sort to the top
                scoredChunks.insert(ScoredChunk(chunk: chunk, relevanceScore: 1.0), at: 0)
            }
        }
    }

    // MARK: - Context Building

    /// Builds LLM context from only the *included* scored chunks.
    private func buildContext(scoredChunks: [ScoredChunk], query: String) -> [ChatMessage] {
        let included = scoredChunks.filter(\.isIncluded)
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

        // Build the chunk context (only included chunks)
        let chunksContext = included.enumerated().map { index, scored in
            """
            [Chunk \(index + 1): \(scored.chunk.id)] (relevance: \(scored.relevancePercent))
            Source: \(scored.chunk.title)
            \(scored.chunk.slideNumber.map { "Slide \($0)" } ?? "")

            \(scored.chunk.content)
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

    // MARK: - Chunk Toggling

    /// Toggle a chunk's `isIncluded` flag. Does not re-run generation automatically;
    /// the user should tap "Regenerate" to re-generate with the new selection.
    func toggleChunk(id: String) {
        if let index = retrievedChunks.firstIndex(where: { $0.id == id }) {
            retrievedChunks[index].isIncluded.toggle()
        }
    }

    /// True when the user has toggled chunks since the last assistant response,
    /// signalling the Regenerate button should appear.
    var hasChunkSelectionChanged: Bool {
        // Show regenerate whenever there are chunks AND an assistant message
        guard !retrievedChunks.isEmpty,
              messages.last?.role == .assistant else { return false }
        return true
    }

    // MARK: - Regenerate

    /// Re-runs only the LLM generation step with the current chunk selection
    /// (skips embedding & search). Replaces the last assistant message.
    func regenerate(provider: LLMProvider) async {
        guard !retrievedChunks.isEmpty else { return }

        // Find the last user query to rebuild the context
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        error = nil

        // Remove the last assistant message so we can replace it
        if messages.last?.role == .assistant {
            messages.removeLast()
        }

        let contextMessages = buildContext(scoredChunks: retrievedChunks, query: lastUserMessage.content)
        let client = LLMServiceFactory.client(for: provider)
        let includedChunks = retrievedChunks.filter(\.isIncluded)
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            referencedChunkIDs: includedChunks.map(\.id)
        )
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        generationTask = Task {
            isGenerating = true
            defer {
                generationTask = nil
                isGenerating = false
            }
            do {
                for try await token in client.chatStream(messages: contextMessages) {
                    if Task.isCancelled { break }
                    messages[assistantIndex].content += token
                }
                if messages[assistantIndex].content.isEmpty && !Task.isCancelled {
                    let fullResponse = try await client.chat(messages: contextMessages)
                    messages[assistantIndex].content = fullResponse
                }
                if Task.isCancelled && !messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content += "\n\n(Stopped)"
                }
                if let cid = currentConversationId, let conversationDB {
                    try? await conversationDB.insertMessage(messages[assistantIndex], conversationId: cid)
                    await refreshConversations()
                }
            } catch is CancellationError {
                if !messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content += "\n\n(Stopped)"
                }
                if let cid = currentConversationId, let conversationDB {
                    try? await conversationDB.insertMessage(messages[assistantIndex], conversationId: cid)
                    await refreshConversations()
                }
            } catch {
                self.error = "Regeneration failed: \(error.localizedDescription)"
            }
        }
        await generationTask?.value
    }

    /// Cancels the current generation (streaming) task. Safe to call when not generating.
    func cancelGeneration() {
        generationTask?.cancel()
    }

    // MARK: - Clear

    func clearConversation() {
        currentConversationId = nil
        messages.removeAll()
        retrievedChunks.removeAll()
        error = nil
    }
}
