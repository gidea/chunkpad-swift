import SwiftUI

// MARK: - Validation State

/// Tracks the state of an API key validation request.
enum APIKeyValidationState: Equatable {
    case idle
    case testing
    case success
    case failure(String)
}

// MARK: - Generation Settings Section

/// Settings sections for LLM provider selection, API keys, model pickers, and validation.
/// Renders three consecutive Form sections: "Generation Model", "Claude (Anthropic)", "ChatGPT (OpenAI)",
/// plus a conditional "Llama Status" section.
struct GenerationSettingsSection: View {
    @Environment(AppState.self) private var appState

    @State private var anthropicValidation: APIKeyValidationState = .idle
    @State private var openaiValidation: APIKeyValidationState = .idle

    var body: some View {
        @Bindable var appState = appState

        providerPickerSection(appState: $appState)
        anthropicSection(appState: $appState)
        openaiSection(appState: $appState)
        llamaStatusSection
    }

    // MARK: - Provider Picker

    @ViewBuilder
    private func providerPickerSection(appState: Bindable<AppState>) -> some View {
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
    }

    // MARK: - Anthropic

    @ViewBuilder
    private func anthropicSection(appState: Bindable<AppState>) -> some View {
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
                    Task { await testAPIKey(for: .anthropic) }
                }
                .controlSize(.small)
                .disabled(appState.wrappedValue.anthropicAPIKey.isEmpty || anthropicValidation == .testing)

                validationIndicator(state: anthropicValidation)
            }
        }
    }

    // MARK: - OpenAI

    @ViewBuilder
    private func openaiSection(appState: Bindable<AppState>) -> some View {
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
                    Task { await testAPIKey(for: .openai) }
                }
                .controlSize(.small)
                .disabled(appState.wrappedValue.openaiAPIKey.isEmpty || openaiValidation == .testing)

                validationIndicator(state: openaiValidation)
            }
        }
    }

    // MARK: - Llama Status (conditional)

    @ViewBuilder
    private var llamaStatusSection: some View {
        if appState.generationMode == .bundled {
            Section("Llama Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(llamaStatusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.bundledLLMStatus.displayText)
                }
                if !appState.bundledLLMStatus.isReady {
                    Text("Download Llama from the Llama (Local) section above to enable on-device generation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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

    // MARK: - Validation Indicator

    @ViewBuilder
    private func validationIndicator(state: APIKeyValidationState) -> some View {
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

    // MARK: - Consolidated API Key Test

    /// Tests an API key by making a lightweight request to the provider's API.
    /// Consolidates the previously duplicated testAnthropicKey/testOpenAIKey methods.
    private func testAPIKey(for provider: CloudProvider) async {
        // Update the appropriate validation state
        switch provider {
        case .anthropic: anthropicValidation = .testing
        case .openai: openaiValidation = .testing
        }

        do {
            let request = buildValidationRequest(for: provider)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                setValidation(.failure("No response"), for: provider)
                return
            }
            if http.statusCode == 200 {
                setValidation(.success, for: provider)
            } else if http.statusCode == 401 {
                setValidation(.failure("Invalid API key"), for: provider)
            } else {
                setValidation(.failure("HTTP \(http.statusCode)"), for: provider)
            }
        } catch {
            setValidation(.failure(error.localizedDescription), for: provider)
        }
    }

    private func buildValidationRequest(for provider: CloudProvider) -> URLRequest {
        switch provider {
        case .anthropic:
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
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.timeoutInterval = 10
            return request

        case .openai:
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(appState.openaiAPIKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            return request
        }
    }

    private func setValidation(_ state: APIKeyValidationState, for provider: CloudProvider) {
        switch provider {
        case .anthropic: anthropicValidation = state
        case .openai: openaiValidation = state
        }
    }
}
