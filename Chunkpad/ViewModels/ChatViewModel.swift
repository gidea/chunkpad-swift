import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.chunkpad", category: "ChatViewModel")

/// A persisted chat conversation (metadata only; messages are stored separately).
/// Declared here so the @Observable macro expansion can resolve the type.
struct Conversation: Identifiable, Sendable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    var messageCount: Int = 0
}

// MARK: - Streaming Error Kind

/// Classifies a network error that occurred during LLM streaming so the UI
/// can display a specific recovery message.
enum StreamingErrorKind: Equatable {
    /// The network connection was lost mid-stream.
    case connectionLost
    /// The API returned HTTP 429 (rate limited). `retryAfter` is seconds from the header if present.
    case rateLimited(retryAfter: Int?)
    /// Any other error — message is shown as-is.
    case other(String)

    var userMessage: String {
        switch self {
        case .connectionLost:
            return "Connection lost. Your partial response is shown above."
        case .rateLimited(let seconds):
            if let s = seconds {
                return "Rate limited. Please wait \(s) second\(s == 1 ? "" : "s") before retrying."
            }
            return "Rate limited. Please wait a moment before retrying."
        case .other(let msg):
            return "Generation failed: \(msg)"
        }
    }

    /// True when the user can sensibly retry right now (not a rate-limit).
    var canRetryNow: Bool {
        if case .rateLimited = self { return false }
        return true
    }
}

/// Orchestrates the full RAG pipeline:
/// 1. Verify documents are indexed (embedding model was downloaded during indexing)
/// 2. Load embedding model from local cache (NEVER triggers a download)
/// 3. Embed user query locally via MLX (with BGE query instruction prefix)
/// 4. Hybrid search (sqlite-vec KNN + FTS5)
/// 5. Build context from retrieved chunks
/// 6. Stream response from selected LLM (cloud or bundled Llama)
///
/// Model download rules:
/// - Embedding model (bge-large-en-v1.5): downloaded ONLY during document indexing, never here.
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

    /// Set when streaming fails with a classified network error.
    /// Drives the in-chat retry banner (6.4).
    var streamingError: StreamingErrorKind?

    /// The last user query text, kept so the retry button can re-send without re-typing.
    var lastUserQuery: String?

    /// The LLM provider that was used for the last message; preserved so retry uses the same.
    var pendingRetryProvider: LLMProvider?

    /// Current conversation id (nil = no conversation selected; new conversation created on first send).
    var currentConversationId: String?

    /// List of past conversations for the sidebar. Refresh via refreshConversations().
    var conversations: [Conversation] = []

    /// Collections available for scoping hybrid search. Populated by refreshCollections().
    var collections: [Collection] = []

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

    /// Number of chunks auto-dropped from the last context build due to token budget.
    var droppedChunkCount = 0

    // MARK: - Context Preview (Epic 14)

    /// Chunks retrieved via search-before-send. Displayed in the search panel;
    /// transferred to `retrievedChunks` when the user sends the message.
    var previewChunks: [ScoredChunk] = []

    /// True while the search-before-send embed+query pipeline is running.
    var isSearchingPreview = false

    /// Derived: true when the search panel has loaded results and the preview is visible.
    var isPreviewActive: Bool { !previewChunks.isEmpty }

    /// Number of chunks currently marked as included in the preview.
    var previewIncludedCount: Int { previewChunks.filter(\.isIncluded).count }

    // MARK: - Pin Documents State

    /// When true, the pin-documents sheet is presented.
    var showPinDocumentsSheet = false

    /// All indexed documents (fetched when the pin sheet opens).
    var indexedDocuments: [IndexedDocument] = []

    /// IDs of documents the user has pinned. Backed by AppState for persistence.
    var pinnedDocumentIDs: Set<String> {
        get { appState?.pinnedDocumentIDs ?? [] }
        set {
            appState?.pinnedDocumentIDs = newValue
            appState?.saveToUserProfile()
        }
    }

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
            clearPreview() // 14.8: switching conversations collapses the search panel
            error = nil
        } catch {
            self.error = "Failed to load conversation: \(error.localizedDescription)"
        }
    }

    /// Refreshes the collection list from the main DB (used by the scope picker in ChatView).
    /// Non-fatal — if the DB call fails, the picker simply shows no collections.
    func refreshCollections() async {
        do {
            try await database.connect()
            collections = try await database.fetchCollections()
        } catch {
            // Non-fatal — scope picker stays empty; user can still query all documents
        }
    }

    /// Refreshes the conversation list from the chat DB (e.g. after creating or adding messages).
    func refreshConversations() async {
        guard let conversationDB else { return }
        do {
            var list = try await conversationDB.fetchConversations(limit: 100)
            for i in list.indices {
                list[i].messageCount = (try? await conversationDB.messageCount(conversationId: list[i].id)) ?? 0
            }
            await MainActor.run { conversations = list }
        } catch {
            // Non-fatal; list stays as-is
        }
    }

    /// Deletes a conversation from the chat DB.
    func deleteConversation(id: String) async {
        guard let conversationDB else { return }
        do {
            try await conversationDB.deleteConversation(id: id)
            if currentConversationId == id {
                currentConversationId = nil
                messages.removeAll()
                retrievedChunks.removeAll()
            }
            await refreshConversations()
        } catch {
            self.error = "Failed to delete conversation: \(error.localizedDescription)"
        }
    }

    /// Renames a conversation.
    func renameConversation(id: String, title: String) async {
        guard let conversationDB else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await conversationDB.updateConversation(id: id, title: trimmed, updatedAt: Date())
            await refreshConversations()
        } catch {
            self.error = "Failed to rename conversation: \(error.localizedDescription)"
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
            if let cid = currentConversationId {
                await persistMessage(userMessage, conversationId: cid)
                if messages.count == 1 {
                    let title = String(text.prefix(50))
                    let trimmed = title.count < text.count ? title + "…" : title
                    await persistConversationTitle(trimmed, conversationId: cid)
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
            let k = max(1, min(appState?.searchResultCount ?? 10, 20))
            let minScore = max(0.0, min(appState?.searchMinScore ?? 0.1, 1.0))
            var scoredChunks = try await database.hybridSearch(
                queryEmbedding: queryEmbedding,
                queryText: text,
                k: k,
                minScore: minScore,
                collectionId: appState?.selectedCollectionId
            )

            // 5b. Merge pinned document chunks (boosted to score 1.0)
            try await addPinnedChunks(to: &scoredChunks)

            retrievedChunks = scoredChunks
            isSearching = false

            // 6. Build context messages for the LLM (only included chunks)
            let contextMessages = buildContext(scoredChunks: scoredChunks, query: text)

            // 7. Stream response from selected LLM (cloud or bundled Llama)
            let client = LLMServiceFactory.client(for: provider)
            let includedChunks = scoredChunks.filter(\.isIncluded)
            let assistantMessage = Message(
                role: .assistant,
                content: "",
                referencedChunkIDs: includedChunks.map(\.id)
            )
            messages.append(assistantMessage)
            let assistantIndex = messages.count - 1

            // Store retry context for 6.4 network error recovery
            lastUserQuery = text
            pendingRetryProvider = provider

            runGeneration(client: client, contextMessages: contextMessages, assistantIndex: assistantIndex)
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
                if let cid = currentConversationId {
                    await persistMessage(errMessage, conversationId: cid)
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
        if let cid = currentConversationId {
            await persistMessage(userMessage, conversationId: cid)
            if messages.count == 1 {
                let title = String(text.prefix(50))
                let trimmed = title.count < text.count ? title + "…" : title
                await persistConversationTitle(trimmed, conversationId: cid)
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
        .local(LocalConfig(
            provider: .bundled,
            temperature: appState?.llmTemperature ?? 0.7,
            maxTokens: appState?.llmMaxTokens ?? 2048
        ))
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

    /// Remove pinned IDs that reference documents no longer in the database.
    func validatePinnedDocuments() async {
        guard !pinnedDocumentIDs.isEmpty else { return }
        do {
            try await database.connect()
            let docs = try await database.listDocuments()
            let validIDs = Set(docs.map(\.id))
            let invalid = pinnedDocumentIDs.subtracting(validIDs)
            if !invalid.isEmpty {
                pinnedDocumentIDs = pinnedDocumentIDs.intersection(validIDs)
            }
        } catch {
            // Non-fatal; keep existing pins
        }
    }

    /// Fetches chunks for all pinned documents and merges them into the
    /// current `retrievedChunks` with a high relevance score (1.0),
    /// avoiding duplicates.
    private func addPinnedChunks(to scoredChunks: inout [ScoredChunk]) async throws {
        guard !pinnedDocumentIDs.isEmpty else { return }

        let existingIDs = Set(scoredChunks.map(\.id))
        // Collect all pinned chunks first, then prepend once to avoid O(n²) inserts at index 0.
        var pinnedChunks: [ScoredChunk] = []
        for docID in pinnedDocumentIDs {
            let chunks = try await database.chunksForDocument(documentID: docID)
            for chunk in chunks where !existingIDs.contains(chunk.id) {
                pinnedChunks.append(ScoredChunk(chunk: chunk, relevanceScore: 1.0, isPinned: true))
            }
        }
        if !pinnedChunks.isEmpty {
            scoredChunks = pinnedChunks + scoredChunks
        }
    }

    // MARK: - Context Preview (Epic 14)

    /// Runs embed → hybridSearch → addPinnedChunks WITHOUT dispatching to the LLM.
    /// Results populate `previewChunks`; the search panel in ChatView auto-expands
    /// because `isPreviewActive` becomes true.
    func searchWithoutSend(query: String) async {
        guard !query.isEmpty,
              (appState?.indexedDocumentCount ?? 0) > 0 else { return }

        isSearchingPreview = true
        defer { isSearchingPreview = false }

        do {
            try await database.connect()
            try await embedder.ensureModelReady()
            let queryEmbedding = try await embedder.embedQuery(query)
            let k = max(1, min(appState?.searchResultCount ?? 10, 20))
            let minScore = max(0.0, min(appState?.searchMinScore ?? 0.1, 1.0))
            var chunks = try await database.hybridSearch(
                queryEmbedding: queryEmbedding,
                queryText: query,
                k: k,
                minScore: minScore,
                collectionId: appState?.selectedCollectionId
            )
            try await addPinnedChunks(to: &chunks)
            previewChunks = chunks
        } catch {
            self.error = "Search preview failed: \(error.localizedDescription)"
        }
    }

    /// Overload used by the search panel's inline collection picker (Task 14.5).
    /// Bypasses `appState.selectedCollectionId` and uses the provided `collectionId` directly.
    /// Pass `nil` for "all documents", or a collection UUID string for a specific collection.
    func searchWithoutSend(query: String, collectionId: String?) async {
        guard !query.isEmpty,
              (appState?.indexedDocumentCount ?? 0) > 0 else { return }

        isSearchingPreview = true
        defer { isSearchingPreview = false }

        do {
            try await database.connect()
            try await embedder.ensureModelReady()
            let queryEmbedding = try await embedder.embedQuery(query)
            let k = max(1, min(appState?.searchResultCount ?? 10, 20))
            let minScore = max(0.0, min(appState?.searchMinScore ?? 0.1, 1.0))
            var chunks = try await database.hybridSearch(
                queryEmbedding: queryEmbedding,
                queryText: query,
                k: k,
                minScore: minScore,
                collectionId: collectionId
            )
            try await addPinnedChunks(to: &chunks)
            previewChunks = chunks
        } catch {
            self.error = "Search preview failed: \(error.localizedDescription)"
        }
    }

    /// Sends using the already-retrieved `previewChunks`, skipping the embed/search steps.
    /// Transfers `previewChunks` → `retrievedChunks`, then runs buildContext → LLM stream.
    /// Falls back to the full `sendMessage` pipeline if `previewChunks` is empty.
    func sendWithPreview(_ text: String, provider: LLMProvider) async {
        guard !text.isEmpty, !previewChunks.isEmpty else {
            await sendMessage(text, provider: provider)
            return
        }

        if currentConversationId == nil {
            await createNewConversation()
            guard currentConversationId != nil else { return }
        }

        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)
        if let cid = currentConversationId {
            await persistMessage(userMessage, conversationId: cid)
            if messages.count == 1 {
                let title = String(text.prefix(50))
                let trimmed = title.count < text.count ? title + "…" : title
                await persistConversationTitle(trimmed, conversationId: cid)
            }
            await refreshConversations()
        }
        error = nil

        // Transfer preview → retrieved; collapse panel (14.8)
        retrievedChunks = previewChunks
        clearPreview()

        let contextMessages = buildContext(scoredChunks: retrievedChunks, query: text)
        let client = LLMServiceFactory.client(for: provider)
        let includedChunks = retrievedChunks.filter(\.isIncluded)
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            referencedChunkIDs: includedChunks.map(\.id)
        )
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        lastUserQuery = text
        pendingRetryProvider = provider

        runGeneration(client: client, contextMessages: contextMessages, assistantIndex: assistantIndex)
        await generationTask?.value
    }

    /// Clears all search preview state and collapses the panel.
    /// Called on send, explicit dismiss, and conversation switch (14.8).
    func clearPreview() {
        previewChunks.removeAll()
    }

    /// Toggles a chunk's `isIncluded` flag in the PREVIEW list (before send).
    func togglePreviewChunk(id: String) {
        if let index = previewChunks.firstIndex(where: { $0.id == id }) {
            previewChunks[index].isIncluded.toggle()
        }
    }

    /// Marks all chunks from a given source path as excluded in the preview.
    /// Used by the "Remove document" button in the grouped panel view (14.3).
    func removePreviewDocument(sourcePath: String) {
        for index in previewChunks.indices where previewChunks[index].chunk.sourcePath == sourcePath {
            previewChunks[index].isIncluded = false
        }
    }

    // MARK: - Context Building

    /// Builds LLM context from only the *included* scored chunks.
    /// Approximate token count for a string (chars / 4).
    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    private func buildContext(scoredChunks: [ScoredChunk], query: String) -> [ChatMessage] {
        var included = scoredChunks.filter(\.isIncluded)

        // Auto-truncate: drop lowest-relevance non-pinned chunks until under budget.
        // Reserve 20% of contextSize for the response.
        let budget = Int(Double(appState?.contextSize ?? 4096) * 0.8)
        let systemTokens = 80 // ~320 chars for system prompt
        let queryTokens = estimateTokens(query) + 30 // overhead for "My question:" framing
        var chunkTokens = included.reduce(0) { $0 + estimateTokens($1.chunk.content) + 10 }
        var totalTokens = systemTokens + queryTokens + chunkTokens

        droppedChunkCount = 0
        while totalTokens > budget && included.count > 1 {
            // Find lowest-relevance non-pinned chunk to drop
            if let dropIndex = included.indices.reversed().first(where: { !included[$0].isPinned }) {
                let dropped = included.remove(at: dropIndex)
                chunkTokens -= estimateTokens(dropped.chunk.content) + 10
                totalTokens = systemTokens + queryTokens + chunkTokens
                droppedChunkCount += 1
            } else {
                break // All remaining chunks are pinned — cannot drop further
            }
        }

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

        // Build the chunk context using a single string to avoid intermediate array allocations.
        var chunksContext = ""
        for (index, scored) in included.enumerated() {
            if index > 0 { chunksContext += "\n\n---\n\n" }
            chunksContext += "[Chunk \(index + 1): \(scored.chunk.id)] (relevance: \(scored.relevancePercent))\n"
            chunksContext += "Source: \(scored.chunk.title)\n"
            if let slide = scored.chunk.slideNumber {
                chunksContext += "Slide \(slide)\n"
            }
            chunksContext += "\n\(scored.chunk.content)"
        }

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

    // MARK: - Chunk Feedback

    /// Persists a feedback signal for a chunk and updates local retrieved-chunks state.
    /// Pass `.neutral` to clear any existing feedback (reverts to 1.0× score multiplier).
    ///
    /// The DB write is async (actor hop to DatabaseService); the local `retrievedChunks`
    /// update happens on MainActor immediately after so the UI re-renders without delay.
    func setChunkFeedback(chunkId: String, type: FeedbackType) async {
        do {
            try await database.connect()
            try await database.setChunkFeedback(chunkId: chunkId, type: type)
            if let index = retrievedChunks.firstIndex(where: { $0.id == chunkId }) {
                retrievedChunks[index].feedbackType = (type == .neutral) ? nil : type
            }
        } catch {
            self.error = "Failed to save feedback: \(error.localizedDescription)"
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
    /// - Parameter retryQuery: If provided, overrides the query used for context building (for retry after error).
    func regenerate(provider: LLMProvider, retryQuery: String? = nil) async {
        guard !retrievedChunks.isEmpty else { return }

        // Find the last user query to rebuild the context
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        error = nil
        streamingError = nil

        // Remove the last assistant message so we can replace it
        if messages.last?.role == .assistant {
            messages.removeLast()
        }

        let query = retryQuery ?? lastUserMessage.content
        let contextMessages = buildContext(scoredChunks: retrievedChunks, query: query)
        let client = LLMServiceFactory.client(for: provider)
        let includedChunks = retrievedChunks.filter(\.isIncluded)
        let assistantMessage = Message(
            role: .assistant,
            content: "",
            referencedChunkIDs: includedChunks.map(\.id)
        )
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        // Refresh retry context in case provider changed
        pendingRetryProvider = provider

        runGeneration(client: client, contextMessages: contextMessages, assistantIndex: assistantIndex)
        await generationTask?.value
    }

    /// Runs the streaming generation pipeline: stream tokens from the LLM, handle cancellation,
    /// classify errors, and persist the assistant message to the conversation DB.
    /// Shared by `sendMessage` and `regenerate` to eliminate duplication.
    private func runGeneration(client: any LLMClient, contextMessages: [ChatMessage], assistantIndex: Int) {
        generationTask = Task {
            isGenerating = true
            streamingError = nil
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
                if let cid = currentConversationId {
                    await persistMessage(messages[assistantIndex], conversationId: cid)
                    await refreshConversations()
                }
            } catch is CancellationError {
                if !messages[assistantIndex].content.isEmpty {
                    messages[assistantIndex].content += "\n\n(Stopped)"
                }
                if let cid = currentConversationId {
                    await persistMessage(messages[assistantIndex], conversationId: cid)
                    await refreshConversations()
                }
            } catch {
                let kind = classify(error)
                streamingError = kind
                self.error = kind.userMessage
                if let cid = currentConversationId {
                    await persistMessage(messages[assistantIndex], conversationId: cid)
                    await refreshConversations()
                }
            }
        }
    }

    /// Cancels the current generation (streaming) task. Safe to call when not generating.
    func cancelGeneration() {
        generationTask?.cancel()
    }

    /// Persists a message to the conversation database with error logging.
    private func persistMessage(_ message: Message, conversationId: String) async {
        guard let conversationDB else { return }
        do {
            try await conversationDB.insertMessage(message, conversationId: conversationId)
        } catch {
            logger.error("Failed to persist message: \(error.localizedDescription)")
        }
    }

    /// Updates conversation title with error logging.
    private func persistConversationTitle(_ title: String, conversationId: String) async {
        guard let conversationDB else { return }
        do {
            try await conversationDB.updateConversation(id: conversationId, title: title, updatedAt: Date())
        } catch {
            logger.error("Failed to update conversation title: \(error.localizedDescription)")
        }
    }

    // MARK: - Streaming Error Classification

    /// Classifies a thrown error from the LLM client into a `StreamingErrorKind`.
    private func classify(_ error: Error, responseHeaders: [String: String]? = nil) -> StreamingErrorKind {
        // URLError: network connection lost
        if let urlError = error as? URLError, urlError.code == .networkConnectionLost {
            return .connectionLost
        }
        // HTTP 429 — look for a message containing "429" or "rate limit"
        let msg = error.localizedDescription.lowercased()
        if msg.contains("429") || msg.contains("rate limit") || msg.contains("too many requests") {
            // Try to parse a Retry-After value from the error description
            let retryAfter: Int? = {
                // Pattern: "retry after N" or "retry-after: N"
                let patterns = ["retry after (\\d+)", "retry-after: (\\d+)"]
                for pattern in patterns {
                    if let range = msg.range(of: pattern, options: .regularExpression),
                       let numStr = msg[range].components(separatedBy: CharacterSet.decimalDigits.inverted).filter({ !$0.isEmpty }).last,
                       let n = Int(numStr) {
                        return n
                    }
                }
                return nil
            }()
            return .rateLimited(retryAfter: retryAfter)
        }
        return .other(error.localizedDescription)
    }

    // MARK: - Retry Last Message

    /// Re-sends the last user query with the same provider, reusing already-retrieved chunks.
    /// Skips embedding/search — only re-runs generation.
    func retryLastMessage() async {
        guard let provider = pendingRetryProvider,
              let query = lastUserQuery else { return }
        streamingError = nil
        await regenerate(provider: provider, retryQuery: query)
    }

    // MARK: - Export (Epic 15)

    /// Formats the entire conversation as a Markdown document with YAML frontmatter.
    /// Caller is responsible for file I/O or clipboard copy.
    func exportAsMarkdown() -> String {
        let title = conversations.first { $0.id == currentConversationId }?.title ?? "Chat"
        let dateStr = ISO8601DateFormatter().string(from: Date())
        let allChunkIDs = Set(messages.flatMap(\.referencedChunkIDs))

        var md = """
        ---
        title: "\(title)"
        date: \(dateStr)
        messages: \(messages.count)
        chunks_referenced: \(allChunkIDs.count)
        ---

        # \(title)

        """

        for message in messages {
            let heading = message.role == .user ? "## You" : "## Assistant"
            let ts = message.timestamp.formatted(date: .abbreviated, time: .shortened)
            md += "\(heading)\n*\(ts)*\n\n\(message.content)\n\n---\n\n"
        }

        if !allChunkIDs.isEmpty {
            md += "## Sources\n\n"
            for id in allChunkIDs.sorted() { md += "- \(id)\n" }
        }

        return md
    }

    /// Returns a filesystem-safe filename for the conversation export.
    func exportFilename(extension ext: String) -> String {
        let title = conversations.first { $0.id == currentConversationId }?.title ?? "Chat"
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let safe = title.components(separatedBy: allowed.inverted).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let today = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let base = safe.isEmpty ? "Chat-\(today)" : safe
        return "\(base).\(ext)"
    }

    /// Converts the markdown export to a `.docx` file using macOS `textutil` (two-step pipeline).
    /// Returns the URL of a temporary `.docx` file; caller moves it to the final destination.
    func exportAsDocx() async throws -> URL {
        let md = exportAsMarkdown()
        let tmp = FileManager.default.temporaryDirectory
        let stem = UUID().uuidString
        let mdURL   = tmp.appendingPathComponent("\(stem).md")
        let htmlURL = tmp.appendingPathComponent("\(stem).html")
        let docxURL = tmp.appendingPathComponent("\(stem).docx")

        try md.write(to: mdURL, atomically: true, encoding: .utf8)
        // Step 1: Markdown → HTML
        try await runShell("/usr/bin/textutil",
                           ["-convert", "html", mdURL.path, "-output", htmlURL.path])
        // Step 2: HTML → DOCX
        try await runShell("/usr/bin/textutil",
                           ["-convert", "docx", htmlURL.path, "-output", docxURL.path])
        try? FileManager.default.removeItem(at: mdURL)
        try? FileManager.default.removeItem(at: htmlURL)
        return docxURL
    }

    /// Runs an external process and returns its stdout as a String.
    /// Throws if the process exits with a non-zero status.
    @discardableResult
    private func runShell(_ executable: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: executable)
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError  = pipe
            p.terminationHandler = { proc in
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    cont.resume(returning: out)
                } else {
                    cont.resume(throwing: NSError(
                        domain: "ExportError",
                        code: Int(proc.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: out.isEmpty ? "textutil failed" : out]
                    ))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }

    // MARK: - Clear

    func clearConversation() {
        currentConversationId = nil
        messages.removeAll()
        retrievedChunks.removeAll()
        error = nil
        clearPreview() // 14.8: clear preview on conversation reset
    }
}
