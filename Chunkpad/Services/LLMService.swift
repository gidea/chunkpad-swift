import Foundation

// MARK: - Chat Message (for LLM API)

struct ChatMessage: Sendable {
    let role: String  // "system", "user", "assistant"
    let content: String
}

// MARK: - LLM Service Protocol

/// Unified interface for all LLM backends (cloud and local).
protocol LLMClient: Sendable {
    /// Send messages and receive the full response.
    func chat(messages: [ChatMessage]) async throws -> String

    /// Send messages and stream the response token by token.
    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
}

// MARK: - LLM Service Factory

enum LLMServiceFactory {

    static func client(for provider: LLMProvider) -> LLMClient {
        switch provider {
        case .cloud(let config):
            switch config.provider {
            case .anthropic:
                return AnthropicClient(apiKey: config.apiKey, model: config.model,
                                       temperature: config.temperature, maxTokens: config.maxTokens)
            case .openai:
                return OpenAIClient(apiKey: config.apiKey, model: config.model,
                                    temperature: config.temperature, maxTokens: config.maxTokens)
            }
        case .local(let config):
            return BundledLLMClient(service: BundledLLMService.shared,
                                    temperature: config.temperature, maxTokens: config.maxTokens)
        }
    }
}

// MARK: - Bundled LLM Client

/// Wraps the BundledLLMService actor to conform to the LLMClient protocol.
/// Uses Llama 3.2 running locally on Apple Silicon via MLX for text generation.
struct BundledLLMClient: LLMClient, Sendable {
    let service: BundledLLMService
    let temperature: Double
    let maxTokens: Int

    func chat(messages: [ChatMessage]) async throws -> String {
        try await service.generate(messages: messages, temperature: temperature, maxTokens: maxTokens)
    }

    func chatStream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        let service = self.service
        let messages = messages
        let temperature = self.temperature
        let maxTokens = self.maxTokens
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = await service.generateStream(
                        messages: messages, temperature: temperature, maxTokens: maxTokens)
                    for try await token in stream {
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError, Sendable {
    case noAPIKey
    case requestFailed(String)
    case invalidResponse
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key configured"
        case .requestFailed(let msg): return "LLM request failed: \(msg)"
        case .invalidResponse: return "Invalid response from LLM"
        case .streamFailed(let msg): return "Stream failed: \(msg)"
        }
    }
}
