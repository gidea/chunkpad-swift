import SwiftUI

/// Settings section showing the on-device embedding model status and configuration.
struct EmbeddingsSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
                        .fill(statusColor)
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
                Text("100% on-device \u{2014} documents never leave your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.embeddingModelStatus {
        case .notDownloaded: return .gray
        case .downloading: return .blue
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }
}
