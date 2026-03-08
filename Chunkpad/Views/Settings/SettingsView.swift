import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            DatabaseSettingsSection()
            EmbeddingsSettingsSection()
            LlamaSettingsSection()
            documentIndexingSection(appState: $appState)
            searchSection(appState: $appState)
            GenerationSettingsSection()
            llmParametersSection(appState: $appState)
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
        .onChange(of: appState.contextSize) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkSizeTokens) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.chunkOverlapTokens) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.searchResultCount) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.searchMinScore) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.llmTemperature) { _, _ in appState.saveToUserProfile() }
        .onChange(of: appState.llmMaxTokens) { _, _ in appState.saveToUserProfile() }
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
                Text("Local MLX embeddings \u{00B7} SQLite + sqlite-vec \u{00B7} Flexible LLM")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
