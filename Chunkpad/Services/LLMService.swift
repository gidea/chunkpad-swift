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
                return AnthropicClient(apiKey: config.apiKey, model: config.model)
            case .openai:
                return OpenAIClient(apiKey: config.apiKey, model: config.model)
            }
        case .local(let config):
            switch config.provider {
            case .ollama:
                return OllamaClient(endpoint: config.endpoint, model: config.modelName)
            case .bundled:
                // Bundled llama.cpp — placeholder for future implementation
                return OllamaClient(endpoint: "http://localhost:11434", model: config.modelName)
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
