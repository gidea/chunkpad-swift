import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var anthropicValidation: ValidationState = .idle
    @State private var openaiValidation: ValidationState = .idle

    // 5.4: Database management state
    @State private var dbFileSize: Int64?
    @State private var dbChunkCount: Int?
    @State private var showClearDatabaseConfirmation = false

    var body: some View {
        @Bindable var appState = appState

        Form {
            databaseSection
            embeddingsSection
            llamaSection
            documentIndexingSection(appState: $appState)
            searchSection(appState: $appState)
            generationSection(appState: $appState)
            llmParametersSection(appState: $appState)
            privacyNote
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: appState.generationMode) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.anthropicModel) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.openaiModel) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.anthropicAPIKey) { _, _ in appState.saveToUserProfile(); anthropicValidation = .idle }
        .onChange(of: appState.openaiAPIKey) { _, _ in appState.saveToUserProfile(); openaiValidation = .idle }
        .onChange(of: appState.contextSize) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkSizeTokens) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkOverlapTokens) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.searchResultCount) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.searchMinScore) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.llmTemperature) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.llmMaxTokens) { _, _ in appState.saveToUserProfile() }
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
            LabeledContent("Documents") {
                Text("\(appState.indexedDocumentCount)")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Chunks") {
                Text(dbChunkCount.map { "\($0)" } ?? "—")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Size") {
                Text(formattedDatabaseSize)
                    .foregroundStyle(.secondary)
            }

            if appState.isDatabaseConnected && appState.indexedDocumentCount > 0 {
                Button("Clear All Data…", role: .destructive) {
                    showClearDatabaseConfirmation = true
                }
                .controlSize(.small)
            }
        }
        .task { await refreshDatabaseStats() }
        .confirmationDialog("Clear All Data", isPresented: $showClearDatabaseConfirmation) {
            Button("Clear Database", role: .destructive) {
                Task { await clearDatabase() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all indexed documents, chunks, and embeddings. This cannot be undone.")
        }
    }

    private var formattedDatabaseSize: String {
        guard let size = dbFileSize else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    private func refreshDatabaseStats() async {
        guard appState.isDatabaseConnected else { return }
        let db = DatabaseService()
        do {
            try await db.connect()
            dbChunkCount = try await db.totalChunkCount()
            dbFileSize = await db.databaseFileSize()
        } catch {
            dbChunkCount = nil
            dbFileSize = nil
        }
    }

    private func clearDatabase() async {
        let db = DatabaseService()
        do {
            try await db.connect()
            try await db.deleteAllData()
            appState.indexedDocumentCount = 0
            dbChunkCount = 0
            await refreshDatabaseStats()
            NotificationCenter.default.post(name: IndexingViewModel.documentDeletedNotification, object: nil)
        } catch {
            // Silently fail; user can retry
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
            LabeledContent("Embedding model") {
                Text("\(EmbeddingService.modelDisplayName) (\(EmbeddingService.embeddingDimension)d)")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Model token limit") {
                Text("\(EmbeddingService.maxTokenWindow) tokens")
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Chunk size (tokens)") {
                TextField(
                    "\(EmbeddingService.maxTokenWindow)",
                    value: appState.chunkSizeTokens,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            if appState.wrappedValue.chunkSizeTokens > EmbeddingService.maxTokenWindow {
                Label(
                    "Chunk size exceeds the embedding model's \(EmbeddingService.maxTokenWindow)-token window. Text beyond this limit will be truncated, losing information.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
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

            Text("Recommended: stay at or below the embedding model's token limit (\(EmbeddingService.maxTokenWindow) tokens). Supported formats: TXT, RTF, DOC, DOCX, ODT, PDF.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search

    @ViewBuilder
    private func searchSection(appState: Bindable<AppState>) -> some View {
        Section("Search") {
            LabeledContent("Max results") {
                TextField(
                    "10",
                    value: appState.searchResultCount,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            LabeledContent("Min relevance score") {
                HStack(spacing: 8) {
                    Slider(value: appState.searchMinScore, in: 0.0...1.0, step: 0.05)
                        .frame(width: 150)
                    Text(String(format: "%.2f", appState.wrappedValue.searchMinScore))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }

            Text("Max results caps the number of document chunks sent to the LLM. Min relevance filters out low-quality matches.")
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

            HStack(spacing: 8) {
                Button("Test API Key") {
                    Task { await testAnthropicKey() }
                }
                .controlSize(.small)
                .disabled(appState.wrappedValue.anthropicAPIKey.isEmpty || anthropicValidation == .testing)

                validationIndicator(state: anthropicValidation)
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

            HStack(spacing: 8) {
                Button("Test API Key") {
                    Task { await testOpenAIKey() }
                }
                .controlSize(.small)
                .disabled(appState.wrappedValue.openaiAPIKey.isEmpty || openaiValidation == .testing)

                validationIndicator(state: openaiValidation)
            }
        }

        // Bundled Llama status (only shown when Llama is selected)
        if appState.wrappedValue.generationMode == .bundled {
            Section("Llama Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(llamaStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.wrappedValue.bundledLLMStatus.displayText)
                }
                if !appState.wrappedValue.bundledLLMStatus.isReady {
                    Text("Download Llama from the Llama (Local) section above to enable on-device generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - LLM Parameters

    @ViewBuilder
    private func llmParametersSection(appState: Bindable<AppState>) -> some View {
        Section("LLM Parameters") {
            LabeledContent("Temperature") {
                HStack(spacing: 8) {
                    Slider(value: appState.llmTemperature, in: 0.0...1.0, step: 0.1)
                        .frame(width: 150)
                    Text(String(format: "%.1f", appState.wrappedValue.llmTemperature))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 30)
                }
            }

            LabeledContent("Max tokens") {
                TextField(
                    "4096",
                    value: appState.llmMaxTokens,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            }

            Text("Temperature controls randomness (0 = focused, 1 = creative). Max tokens caps response length.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    // MARK: - API Validation

    @ViewBuilder
    private func validationIndicator(state: ValidationState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    private func testAnthropicKey() async {
        anthropicValidation = .testing
        do {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(appState.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let body: [String: Any] = [
                "model": appState.anthropicModel,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "hi"]]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 10
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                anthropicValidation = .failure("No response")
                return
            }
            if http.statusCode == 200 {
                anthropicValidation = .success
            } else if http.statusCode == 401 {
                anthropicValidation = .failure("Invalid API key")
            } else {
                anthropicValidation = .failure("HTTP \(http.statusCode)")
            }
        } catch {
            anthropicValidation = .failure(error.localizedDescription)
        }
    }

    private func testOpenAIKey() async {
        openaiValidation = .testing
        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(appState.openaiAPIKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                openaiValidation = .failure("No response")
                return
            }
            if http.statusCode == 200 {
                openaiValidation = .success
            } else if http.statusCode == 401 {
                openaiValidation = .failure("Invalid API key")
            } else {
                openaiValidation = .failure("HTTP \(http.statusCode)")
            }
        } catch {
            openaiValidation = .failure(error.localizedDescription)
        }
    }

}

// MARK: - Validation State

private enum ValidationState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}
