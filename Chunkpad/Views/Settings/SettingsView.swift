import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            databaseSection
            embeddingsSection
            llamaSection
            documentIndexingSection(appState: $appState)
            generationSection(appState: $appState)
            privacyNote
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: appState.generationMode) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.anthropicModel) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.openaiModel) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.anthropicAPIKey) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.openaiAPIKey) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.ollamaEndpoint) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.ollamaModel) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.contextSize) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkSizeTokens) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkOverlapTokens) { _, _ in appState.saveToUserProfile() }
    }

    // MARK: - Database

    private var databaseSection: some View {
        Section("Database") {
            LabeledContent("Engine") {
                Text("SQLite + sqlite-vec")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isDatabaseConnected ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.isDatabaseConnected ? "Connected" : "Not Connected")
                }
            }
            LabeledContent("Location") {
                Text("~/Library/Application Support/Chunkpad/")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appState.indexedDocumentCount > 0 {
                LabeledContent("Indexed Documents") {
                    Text("\(appState.indexedDocumentCount)")
                }
            }
        }
    }

    // MARK: - Embeddings

    private var embeddingsSection: some View {
        Section("Embeddings (Local via MLX)") {
            LabeledContent("Model") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(EmbeddingService.modelDisplayName)
                    Text(EmbeddingService.modelID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            LabeledContent("Size") {
                Text(EmbeddingService.modelSize)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Dimensions") {
                Text("\(EmbeddingService.embeddingDimension)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(embeddingStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.embeddingModelStatus.displayText)

                    if case .downloading(let progress) = appState.embeddingModelStatus {
                        ProgressView(value: progress)
                            .frame(width: 80)
                    }
                }
            }
            if case .notDownloaded = appState.embeddingModelStatus {
                Text("The model will be downloaded automatically when you first index documents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Framework") {
                Text("MLX Swift on Apple Silicon")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Cache") {
                Text(EmbeddingService.cacheDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Privacy") {
                Text("100% on-device — documents never leave your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var embeddingStatusColor: Color {
        switch appState.embeddingModelStatus {
        case .notDownloaded: return .gray
        case .downloading: return .blue
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    // MARK: - Llama (Local)

    private var llamaSection: some View {
        Section("Llama (Local)") {
            LabeledContent("Model") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(BundledLLMService.modelDisplayName)
                    Text(BundledLLMService.modelID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            LabeledContent("Size") {
                Text(BundledLLMService.modelSize)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(llamaStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.bundledLLMStatus.displayText)
                    if case .downloading(let progress) = appState.bundledLLMStatus {
                        ProgressView(value: progress)
                            .frame(width: 80)
                    }
                }
            }
            LabeledContent("Cache") {
                Text(BundledLLMService.cacheDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !appState.bundledLLMStatus.isReady {
                Button("Download Llama") {
                    Task {
                        try? await BundledLLMService.shared.downloadAndLoad()
                    }
                }
                .disabled(llamaStatusIsBusy)
            }
            if appState.bundledLLMStatus.isReady {
                Button("Remove from memory", role: .destructive) {
                    Task {
                        await BundledLLMService.shared.unload()
                    }
                }
            }
            Text("Llama 3.2 runs on-device for chat when no API key is set. To free disk space, delete the cache folder manually.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var llamaStatusColor: Color {
        switch appState.bundledLLMStatus {
        case .notDownloaded: return .gray
        case .downloading: return .blue
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    private var llamaStatusIsBusy: Bool {
        if case .downloading = appState.bundledLLMStatus { return true }
        if case .loading = appState.bundledLLMStatus { return true }
        return false
    }

    // MARK: - Document Indexing

    @ViewBuilder
    private func documentIndexingSection(appState: Bindable<AppState>) -> some View {
        Section("Document Indexing") {
            LabeledContent("Chunk size (tokens)") {
                TextField(
                    "1000",
                    value: appState.chunkSizeTokens,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            LabeledContent("Overlap (tokens)") {
                TextField(
                    "100",
                    value: appState.chunkOverlapTokens,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            LabeledContent("Approx. characters per chunk") {
                Text("~\(appState.wrappedValue.chunkSizeChars)")
                    .foregroundStyle(.secondary)
            }

            Text("Approximate; uses ~4 characters per token. Supported formats: TXT, RTF, DOC, DOCX, ODT, PDF.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generation Model

    @ViewBuilder
    private func generationSection(appState: Bindable<AppState>) -> some View {
        Section("Generation Model") {
            Picker("Provider", selection: appState.generationMode) {
                ForEach(GenerationMode.allCases) { mode in
                    Label {
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                            Text(mode.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: mode.icon)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
        }

        // Always show API key + model fields so users can configure both and switch freely
        Section("Claude (Anthropic)") {
            SecureField("API Key", text: appState.anthropicAPIKey, prompt: Text("sk-ant-..."))
                .textFieldStyle(.roundedBorder)

            Picker("Model", selection: appState.anthropicModel) {
                ForEach(CloudProvider.anthropic.availableModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }

        Section("ChatGPT (OpenAI)") {
            SecureField("API Key", text: appState.openaiAPIKey, prompt: Text("sk-..."))
                .textFieldStyle(.roundedBorder)

            Picker("Model", selection: appState.openaiModel) {
                ForEach(CloudProvider.openai.availableModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
        }

        // Ollama-specific settings (only shown when Ollama is selected)
        if appState.wrappedValue.generationMode == .ollama {
            Section("Ollama Configuration") {
                TextField("Endpoint", text: appState.ollamaEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: appState.ollamaModel, prompt: Text("llama3.3"))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Privacy Note

    @ViewBuilder
    private var privacyNote: some View {
        Section {
            if appState.generationMode.isCloud {
                Label(
                    "Only your query and small text chunks are sent to the cloud. Full documents stay on your Mac.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Everything runs on-device. Nothing is sent to the cloud.",
                    systemImage: "lock.shield.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text("0.1.0")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Architecture") {
                Text("Local MLX embeddings · SQLite + sqlite-vec · Flexible LLM")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
