import Foundation
import MLXLLM
import MLXLMCommon

// MARK: - Bundled LLM Status

/// Tracks the lifecycle of the bundled Llama model for local text generation.
/// Completely separate from the embedding model (bge-base-en-v1.5).
///
/// - The embedding model creates vector embeddings for search (MLXEmbedders).
/// - This model generates text responses from retrieved context (MLXLLM).
enum BundledLLMStatus: Sendable, Equatable {
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

// MARK: - Bundled LLM Service

/// Manages the lifecycle of the bundled Llama 3.2 model for local text generation.
///
/// This is a LOCAL GENERATIVE LLM — it answers questions from retrieved context,
/// just like Claude, ChatGPT, or Ollama. It is NOT an embedding model.
///
/// The model is NOT included in the app bundle. It is downloaded from HuggingFace
/// only when the user explicitly accepts the download offer (triggered when they
/// try to chat without a Claude or ChatGPT API key configured).
///
/// Download trigger:
///   User sends chat message → no cloud API key → app offers Llama → user accepts → download.
///   The model is NEVER downloaded automatically or at app launch.
actor BundledLLMService {

    // MARK: - Singleton

    /// Shared instance — the loaded model persists for the app lifetime.
    static let shared = BundledLLMService()

    // MARK: - Configuration

    /// HuggingFace model ID for MLX-optimized Llama 3.2 (4-bit quantized).
    static let modelID = "mlx-community/Llama-3.2-3B-Instruct-4bit"
    static let modelDisplayName = "Llama 3.2 (3B, 4-bit)"
    static let modelSize = "~1.7 GB"

    // MARK: - State

    private(set) var status: BundledLLMStatus = .notDownloaded
    private var container: ModelContainer?

    /// Callback invoked on status changes, used to drive UI updates.
    private var onStatusChange: (@Sendable (BundledLLMStatus) -> Void)?

    /// Set the status callback. Call this before downloadAndLoad().
    func setStatusCallback(_ callback: @escaping @Sendable (BundledLLMStatus) -> Void) {
        onStatusChange = callback
    }

    /// Current status (for Settings and other UI).
    func getStatus() async -> BundledLLMStatus {
        status
    }

    /// Display path for the Llama model cache (MLX cache directory).
    static let cacheDisplayPath = "~/Library/Caches/org.mlx.mlx-lm"

    // MARK: - Download & Load

    /// Downloads Llama 3.2 from HuggingFace and loads it into memory.
    /// Safe to call multiple times — no-ops if already ready, waits if in progress.
    func downloadAndLoad() async throws {
        switch status {
        case .ready:
            return  // Already good
        case .downloading, .loading:
            // Another task is loading — wait for it to finish
            while !status.isReady {
                if case .error(let msg) = status { throw LLMError.requestFailed(msg) }
                try await Task.sleep(for: .milliseconds(200))
            }
            return
        case .notDownloaded, .error:
            break  // Proceed to download + load
        }

        do {
            // Phase 1: Download model weights from HuggingFace (cached after first download)
            updateStatus(.downloading(progress: 0))

            let configuration = ModelConfiguration(id: Self.modelID)
            let loadedContainer = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            ) { [weak self] progress in
                guard let self else { return }
                let fraction = progress.fractionCompleted
                Task { await self.updateStatus(.downloading(progress: fraction)) }
            }

            // Phase 2: Model is loaded — tokenizer, weights, and processor are ready
            updateStatus(.loading)
            container = loadedContainer

            updateStatus(.ready)
        } catch {
            updateStatus(.error(error.localizedDescription))
            throw LLMError.requestFailed("Failed to download Llama: \(error.localizedDescription)")
        }
    }

    /// Unloads the model from memory and resets status. Does not delete the cache from disk.
    func unload() {
        container = nil
        updateStatus(.notDownloaded)
    }

    // MARK: - Generate (Non-streaming)

    /// Generate a complete response from the given messages.
    func generate(messages: [ChatMessage]) async throws -> String {
        guard let container, status.isReady else {
            throw LLMError.requestFailed("Bundled LLM not loaded. Download Llama first.")
        }

        let mlxMessages = messages.map { ["role": $0.role, "content": $0.content] }

        let fullText: String = try await container.perform { context in
            let userInput = UserInput(messages: mlxMessages)
            let input = try await context.processor.prepare(input: userInput)

            let parameters = GenerateParameters(temperature: 0.6)
            var detokenizer = NaiveStreamingDetokenizer(tokenizer: context.tokenizer)
            var output = ""

            let _ = try MLXLMCommon.generate(
                input: input, parameters: parameters, context: context
            ) { tokens in
                if let last = tokens.last {
                    detokenizer.append(token: last)
                }
                if let new = detokenizer.next() {
                    output += new
                }
                return tokens.count >= 2048 ? .stop : .more
            }

            return output
        }

        return fullText
    }

    // MARK: - Generate (Streaming)

    /// Stream a response token-by-token from the given messages.
    func generateStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        // Capture references while on the actor
        guard let container, status.isReady else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMError.requestFailed("Bundled LLM not loaded."))
            }
        }

        let mlxMessages = messages.map { ["role": $0.role, "content": $0.content] }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await container.perform { context in
                        let userInput = UserInput(messages: mlxMessages)
                        let input = try await context.processor.prepare(input: userInput)

                        let parameters = GenerateParameters(temperature: 0.6)
                        var detokenizer = NaiveStreamingDetokenizer(tokenizer: context.tokenizer)

                        let _ = try MLXLMCommon.generate(
                            input: input, parameters: parameters, context: context
                        ) { tokens in
                            if let last = tokens.last {
                                detokenizer.append(token: last)
                            }
                            if let new = detokenizer.next() {
                                continuation.yield(new)
                            }
                            return tokens.count >= 2048 ? .stop : .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateStatus(_ newStatus: BundledLLMStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }
}
