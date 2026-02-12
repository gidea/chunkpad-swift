import SwiftUI

@Observable
@MainActor
final class AppState {

    // MARK: - Navigation

    /// Unified sidebar selection: chat (with optional conversation), documents, or settings.
    var selectedItem: SidebarSelection = .chat(conversationId: nil)

    /// Derived tab for switching to documents/settings. Used by "Open Settings" etc.
    var selectedTab: SidebarTab {
        switch selectedItem {
        case .chat: return .chat
        case .documents: return .documents
        case .settings: return .settings
        }
    }

    // MARK: - Generation (LLM Selection)

    var generationMode: GenerationMode = .anthropic

    // Cloud API keys and model selection
    var anthropicAPIKey: String = ""
    var anthropicModel: String = CloudProvider.anthropic.defaultModel
    var openaiAPIKey: String = ""
    var openaiModel: String = CloudProvider.openai.defaultModel

    // Local LLM settings (Ollama)
    var ollamaEndpoint: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.3"
    var contextSize: Int = 4096

    // MARK: - Document Indexing (Chunking Strategy)

    /// Target chunk size in tokens. Uses ~4 characters per token approximation.
    var chunkSizeTokens: Int = 1000
    /// Overlap between consecutive chunks in tokens (~10% of chunk size).
    var chunkOverlapTokens: Int = 100

    /// Derived chunk size in characters (tokens × 4).
    var chunkSizeChars: Int { chunkSizeTokens * 4 }
    /// Derived overlap in characters (tokens × 4).
    var chunkOverlapChars: Int { chunkOverlapTokens * 4 }

    // MARK: - Database Status

    var isDatabaseConnected = false
    var indexedDocumentCount = 0

    /// Separate SQLite DB for conversations and messages only (chunkpad_chat.db).
    /// Connected at launch in ChunkpadApp.
    let conversationDatabase = ConversationDatabaseService()

    // MARK: - Embedding Status

    /// Tracks the embedding model lifecycle across the app.
    /// Updated by EmbeddingService via its onStatusChange callback.
    var embeddingModelStatus: EmbeddingModelStatus = .notDownloaded

    // MARK: - Bundled Llama Status

    /// Tracks the bundled Llama 3.2 model lifecycle. Updated by BundledLLMService via callback.
    var bundledLLMStatus: BundledLLMStatus = .notDownloaded

    // MARK: - User Profile Persistence

    private static let defaults = UserDefaults.standard
    private enum ProfileKey {
        static let generationMode = "profile_generation_mode"
        static let anthropicModel = "profile_anthropic_model"
        static let openaiModel = "profile_openai_model"
        static let ollamaEndpoint = "profile_ollama_endpoint"
        static let ollamaModel = "profile_ollama_model"
        static let contextSize = "profile_context_size"
        static let chunkSizeTokens = "profile_chunk_size_tokens"
        static let chunkOverlapTokens = "profile_chunk_overlap_tokens"
    }

    private static let keychainAnthropic = "anthropic_api_key"
    private static let keychainOpenAI = "openai_api_key"

    /// Load settings and API keys from UserDefaults and Keychain. Call once at launch.
    func loadFromUserProfile() {
        if let raw = Self.defaults.string(forKey: ProfileKey.generationMode),
           let mode = GenerationMode(rawValue: raw) {
            generationMode = mode
        }
        anthropicModel = Self.defaults.string(forKey: ProfileKey.anthropicModel) ?? CloudProvider.anthropic.defaultModel
        openaiModel = Self.defaults.string(forKey: ProfileKey.openaiModel) ?? CloudProvider.openai.defaultModel
        ollamaEndpoint = Self.defaults.string(forKey: ProfileKey.ollamaEndpoint) ?? "http://localhost:11434"
        ollamaModel = Self.defaults.string(forKey: ProfileKey.ollamaModel) ?? "llama3.3"
        contextSize = Self.defaults.object(forKey: ProfileKey.contextSize) as? Int ?? 4096
        chunkSizeTokens = Self.defaults.object(forKey: ProfileKey.chunkSizeTokens) as? Int ?? 1000
        chunkOverlapTokens = Self.defaults.object(forKey: ProfileKey.chunkOverlapTokens) as? Int ?? 100
        anthropicAPIKey = KeychainHelper.get(account: Self.keychainAnthropic) ?? ""
        openaiAPIKey = KeychainHelper.get(account: Self.keychainOpenAI) ?? ""
    }

    /// Persist current settings and API keys. Call when any persisted property changes (e.g. from Settings).
    func saveToUserProfile() {
        Self.defaults.set(generationMode.rawValue, forKey: ProfileKey.generationMode)
        Self.defaults.set(anthropicModel, forKey: ProfileKey.anthropicModel)
        Self.defaults.set(openaiModel, forKey: ProfileKey.openaiModel)
        Self.defaults.set(ollamaEndpoint, forKey: ProfileKey.ollamaEndpoint)
        Self.defaults.set(ollamaModel, forKey: ProfileKey.ollamaModel)
        Self.defaults.set(contextSize, forKey: ProfileKey.contextSize)
        Self.defaults.set(chunkSizeTokens, forKey: ProfileKey.chunkSizeTokens)
        Self.defaults.set(chunkOverlapTokens, forKey: ProfileKey.chunkOverlapTokens)
        if anthropicAPIKey.isEmpty {
            KeychainHelper.remove(account: Self.keychainAnthropic)
        } else {
            KeychainHelper.set(anthropicAPIKey, forAccount: Self.keychainAnthropic)
        }
        if openaiAPIKey.isEmpty {
            KeychainHelper.remove(account: Self.keychainOpenAI)
        } else {
            KeychainHelper.set(openaiAPIKey, forAccount: Self.keychainOpenAI)
        }
    }

    // MARK: - Resolve Provider

    /// Builds the concrete `LLMProvider` from the current settings.
    func resolvedProvider() -> LLMProvider? {
        switch generationMode {
        case .anthropic:
            guard !anthropicAPIKey.isEmpty else { return nil }
            return .cloud(CloudConfig(provider: .anthropic, apiKey: anthropicAPIKey, model: anthropicModel))
        case .openai:
            guard !openaiAPIKey.isEmpty else { return nil }
            return .cloud(CloudConfig(provider: .openai, apiKey: openaiAPIKey, model: openaiModel))
        case .ollama:
            return .local(LocalConfig(
                provider: .ollama,
                endpoint: ollamaEndpoint,
                modelName: ollamaModel,
                contextSize: contextSize
            ))
        }
    }

    // MARK: - Sidebar Selection

    enum SidebarSelection: Hashable {
        case chat(conversationId: String?)
        case documents
        case settings
    }

    // MARK: - Sidebar Tabs

    enum SidebarTab: String, CaseIterable, Identifiable {
        case chat = "Chat"
        case documents = "Documents"
        case settings = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right"
            case .documents: return "doc.on.doc"
            case .settings: return "gear"
            }
        }
    }
}
