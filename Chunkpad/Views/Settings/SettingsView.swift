import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            databaseSection
            embeddingsSection
            generationSection(appState: $appState)
            privacyNote
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
                Text("The model will be downloaded automatically when you first index documents or search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Framework") {
                Text("MLX Swift on Apple Silicon")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Cache") {
                Text("~/.cache/huggingface/hub/")
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

    // MARK: - Generation Model

    private func generationSection(appState: Bindable<AppState>) -> some View {
        Section("Generation Model") {
            Picker("Mode", selection: appState.generationMode) {
                ForEach(GenerationMode.allCases) { mode in
                    Label {
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                        }
                    } icon: {
                        Image(systemName: mode.icon)
                    }
                    .tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            switch appState.wrappedValue.generationMode {
            case .anthropic:
                SecureField("Anthropic API Key", text: appState.anthropicAPIKey, prompt: Text("sk-ant-..."))
                    .textFieldStyle(.roundedBorder)
            case .openai:
                SecureField("OpenAI API Key", text: appState.openaiAPIKey, prompt: Text("sk-..."))
                    .textFieldStyle(.roundedBorder)
            case .ollama:
                TextField("Endpoint", text: appState.ollamaEndpoint)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: appState.ollamaModel, prompt: Text("llama3.3"))
                    .textFieldStyle(.roundedBorder)
            case .bundled:
                TextField("Model", text: appState.bundledModel, prompt: Text("llama-3.2-3b"))
                    .textFieldStyle(.roundedBorder)
                LabeledContent("Context Size") {
                    Text("\(appState.wrappedValue.contextSize) tokens")
                        .foregroundStyle(.secondary)
                }
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
