import Foundation
import MLX
import MLXEmbedders

// MARK: - Model Status

/// Tracks the lifecycle of the embedding model: not yet downloaded → downloading → ready.
/// The model is never bundled with the app — it's downloaded on demand.
enum EmbeddingModelStatus: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var displayText: String {
        switch self {
        case .notDownloaded: return "Not Downloaded"
        case .downloading(let p): return "Downloading \(Int(p * 100))%"
        case .loading: return "Loading into memory..."
        case .ready: return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Embedding Service

/// Generates vector embeddings locally on Apple Silicon using MLX.
///
/// Uses BAAI/bge-base-en-v1.5 — a high-quality BERT-based embedding model
/// optimized for retrieval-augmented generation (RAG). Key properties:
/// - 768-dimensional embeddings
/// - CLS pooling (configured from model's 1_Pooling/config.json)
/// - ~438 MB download (model weights in safetensors format)
/// - Cosine similarity for distance metric
///
/// The model is NOT bundled with the app. It is downloaded from HuggingFace
/// ONLY when the user triggers document indexing (selects files to chunk and embed).
/// It is NEVER downloaded from the chat path — the user must index documents first.
/// After download it's cached locally and loads instantly on subsequent runs.
///
/// BGE uses a query instruction prefix for retrieval queries:
/// - Documents/passages: embedded as-is (no prefix)
/// - Queries: prefixed with "Represent this sentence for searching relevant passages: "
actor EmbeddingService {

    // MARK: - Configuration

    /// The model configuration — pre-registered in MLXEmbedders.
    static let modelConfiguration = ModelConfiguration.bge_base

    /// The dimensionality of output embeddings (768 for bge-base-en-v1.5).
    static let embeddingDimension: Int = 768

    /// BGE query instruction prefix for retrieval tasks.
    static let queryInstruction = "Represent this sentence for searching relevant passages: "

    /// Model name for display in UI.
    static let modelDisplayName = "bge-base-en-v1.5"
    static let modelID = "BAAI/bge-base-en-v1.5"
    static let modelSize = "~438 MB"

    /// Where the embedding model is cached on disk after download.
    /// MLXEmbedders stores downloaded models here via its internal hub library.
    static let cacheDirectory = "~/.cache/huggingface/hub/"

    /// User-facing description of the cache location (no third-party branding).
    static let cacheDisplayPath = "~/.cache/"

    // MARK: - State

    private(set) var status: EmbeddingModelStatus = .notDownloaded

    /// The loaded model container (actor wrapping model + tokenizer + pooler).
    private var container: ModelContainer?

    // MARK: - Status Callback

    /// Callback invoked on status changes, used to drive UI updates.
    private var onStatusChange: (@Sendable (EmbeddingModelStatus) -> Void)?

    /// Set the status callback. Call this before ensureModelReady().
    func setStatusCallback(_ callback: @escaping @Sendable (EmbeddingModelStatus) -> Void) {
        onStatusChange = callback
    }

    // MARK: - Ensure Model Ready

    /// Downloads the model if needed, loads it into memory, and returns when ready.
    /// This is the single entry point — call it before any embed() call.
    /// Safe to call multiple times; no-ops if already ready.
    func ensureModelReady() async throws {
        switch status {
        case .ready:
            return  // Already good
        case .downloading, .loading:
            // Another task is loading — wait for it to finish
            while !status.isReady {
                if case .error(let msg) = status { throw EmbeddingError.inferenceFailed(msg) }
                try await Task.sleep(for: .milliseconds(200))
            }
            return
        case .notDownloaded, .error:
            break  // Proceed to download + load
        }

        do {
            // Phase 1: Download model weights (cached after first download)
            updateStatus(.downloading(progress: 0))

            let loadedContainer = try await loadModelContainer(
                configuration: Self.modelConfiguration,
                progressHandler: { [weak self] progress in
                    guard let self else { return }
                    let fraction = progress.fractionCompleted
                    Task { await self.updateStatus(.downloading(progress: fraction)) }
                }
            )

            // Phase 2: Assign container — model, tokenizer, and pooler are ready
            updateStatus(.loading)
            container = loadedContainer

            updateStatus(.ready)
        } catch {
            updateStatus(.error(error.localizedDescription))
            throw EmbeddingError.inferenceFailed(error.localizedDescription)
        }
    }

    // MARK: - Embed Document Text

    /// Embed a passage/document chunk. No query instruction prefix.
    /// Use this for indexing documents into sqlite-vec.
    func embed(_ text: String) async throws -> [Float] {
        guard let container, status.isReady else {
            throw EmbeddingError.modelNotLoaded
        }

        // ModelContainer.perform gives us (EmbeddingModel, Tokenizer, Pooling)
        // The pooler automatically applies CLS pooling (from 1_Pooling/config.json)
        // and L2 normalization when normalize: true
        return await container.perform { model, tokenizer, pooler in
            let tokens = tokenizer.encode(text: text)
            let inputIDs = MLXArray(tokens).reshaped(1, tokens.count)

            // Forward pass through BERT → EmbeddingModelOutput
            let output = model(inputIDs, positionIds: nil, tokenTypeIds: nil, attentionMask: nil)

            // Pool (CLS for BGE) and L2-normalize
            let embedding = pooler(output, normalize: true)

            // Must eval before crossing actor boundary (MLXArray is not Sendable)
            eval(embedding)

            // Convert to [Float] array for sqlite-vec storage
            return Self.toFloatArray(embedding)
        }
    }

    /// Embed a user query. Prepends the BGE query instruction for better retrieval.
    /// Use this when searching sqlite-vec for relevant chunks.
    func embedQuery(_ query: String) async throws -> [Float] {
        let prefixed = Self.queryInstruction + query
        return try await embed(prefixed)
    }

    /// Embed a batch of document texts (no query prefix).
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        guard status.isReady else {
            throw EmbeddingError.modelNotLoaded
        }

        // Process sequentially to keep memory usage bounded on large batches
        var results: [[Float]] = []
        results.reserveCapacity(texts.count)
        for text in texts {
            let embedding = try await embed(text)
            results.append(embedding)
        }
        return results
    }

    // MARK: - Helpers

    private func updateStatus(_ newStatus: EmbeddingModelStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }

    /// Convert a 2D MLXArray [1, dim] to a flat Swift [Float] array.
    private static func toFloatArray(_ array: MLXArray) -> [Float] {
        let flat = array.reshaped(-1)
        return flat.asArray(Float.self)
    }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError, Sendable {
    case modelNotLoaded
    case modelNotDownloaded
    case tokenizationFailed
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Embedding model not loaded into memory"
        case .modelNotDownloaded: return "Embedding model not downloaded yet"
        case .tokenizationFailed: return "Failed to tokenize input text"
        case .inferenceFailed(let msg): return "Embedding inference failed: \(msg)"
        }
    }
}
