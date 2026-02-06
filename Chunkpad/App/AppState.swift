import SwiftUI

@Observable
@MainActor
final class AppState {

    // MARK: - Navigation

    var selectedTab: SidebarTab = .chat

    // MARK: - Generation (LLM Selection)

    var generationMode: GenerationMode = .anthropic

    // Cloud API keys
    var anthropicAPIKey: String = ""
    var openaiAPIKey: String = ""

    // Local LLM settings
    var ollamaEndpoint: String = "http://localhost:11434"
    var ollamaModel: String = "llama3.3"
    var bundledModel: String = "llama-3.2-3b"
    var contextSize: Int = 4096

    // MARK: - Database Status

    var isDatabaseConnected = false
    var indexedDocumentCount = 0

    // MARK: - Embedding Status

    /// Tracks the embedding model lifecycle across the app.
    /// Updated by EmbeddingService via its onStatusChange callback.
    var embeddingModelStatus: EmbeddingModelStatus = .notDownloaded

    // MARK: - Resolve Provider

    /// Builds the concrete `LLMProvider` from the current settings.
    func resolvedProvider() -> LLMProvider? {
        switch generationMode {
        case .anthropic:
            guard !anthropicAPIKey.isEmpty else { return nil }
            return .cloud(CloudConfig(provider: .anthropic, apiKey: anthropicAPIKey))
        case .openai:
            guard !openaiAPIKey.isEmpty else { return nil }
            return .cloud(CloudConfig(provider: .openai, apiKey: openaiAPIKey))
        case .ollama:
            return .local(LocalConfig(
                provider: .ollama,
                endpoint: ollamaEndpoint,
                modelName: ollamaModel,
                contextSize: contextSize
            ))
        case .bundled:
            return .local(LocalConfig(
                provider: .bundled,
                modelName: bundledModel,
                contextSize: contextSize
            ))
        }
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
