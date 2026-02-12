import Foundation

// MARK: - LLM Provider (Service Layer)

/// The resolved provider used by the LLM service at runtime.
/// Embeddings are always local via MLX — this is strictly for text generation.
enum LLMProvider: Sendable {
    case cloud(CloudConfig)
    case local(LocalConfig)

    var isLocal: Bool {
        if case .local = self { return true }
        return false
    }
}

// MARK: - Cloud Configuration

struct CloudConfig: Sendable {
    let provider: CloudProvider
    let apiKey: String
    let model: String

    init(provider: CloudProvider, apiKey: String, model: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model ?? provider.defaultModel
    }
}

/// A specific model offered by a cloud LLM provider.
struct CloudModel: Identifiable, Hashable, Sendable {
    /// The API model identifier sent in requests (e.g. "gpt-4o").
    let id: String
    /// User-facing display name (e.g. "GPT-4o").
    let displayName: String
}

enum CloudProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-sonnet-4-5"
        case .openai: return "gpt-5.2"
        }
    }

    /// Models available for selection in Settings.
    var availableModels: [CloudModel] {
        switch self {
        case .anthropic:
            return [
                CloudModel(id: "claude-opus-4-6", displayName: "Claude Opus 4.6"),
                CloudModel(id: "claude-sonnet-4-5", displayName: "Claude Sonnet 4.5"),
                CloudModel(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5"),
            ]
        case .openai:
            return [
                CloudModel(id: "gpt-5.2", displayName: "GPT-5.2"),
                CloudModel(id: "o4-mini", displayName: "o4-mini"),
            ]
        }
    }
}

// MARK: - Local Configuration

struct LocalConfig: Sendable {
    let provider: LocalProvider
    let endpoint: String
    let modelName: String
    let contextSize: Int

    init(provider: LocalProvider, endpoint: String = "", modelName: String = "", contextSize: Int = 4096) {
        self.provider = provider
        self.endpoint = endpoint.isEmpty ? provider.defaultEndpoint : endpoint
        self.modelName = modelName.isEmpty ? provider.defaultModel : modelName
        self.contextSize = contextSize
    }
}

enum LocalProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case ollama
    case bundled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .bundled: return "Bundled (llama.cpp)"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .bundled: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return "llama3.3"
        case .bundled: return "llama-3.2-3b"
        }
    }
}

// MARK: - Generation Mode (UI Binding)

/// Flat enum for SwiftUI picker binding.
/// Maps to the richer `LLMProvider` type when constructing services.
///
/// Note: The bundled llama.cpp option is intentionally excluded here.
/// It is reserved for internal text generation within the RAG pipeline
/// and not exposed as a user-selectable chat model.
enum GenerationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openai
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .ollama: return "Ollama"
        }
    }

    var icon: String {
        switch self {
        case .anthropic: return "cloud"
        case .openai: return "cloud.fill"
        case .ollama: return "server.rack"
        }
    }

    var subtitle: String {
        switch self {
        case .anthropic: return "Anthropic · Bring your own key"
        case .openai: return "OpenAI · Bring your own key"
        case .ollama: return "Local · Free · Requires Ollama running"
        }
    }

    var isLocal: Bool {
        switch self {
        case .anthropic, .openai: return false
        case .ollama: return true
        }
    }

    var isCloud: Bool { !isLocal }
}
