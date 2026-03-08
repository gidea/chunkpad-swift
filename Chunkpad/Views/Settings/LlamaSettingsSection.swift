import SwiftUI

/// Settings section for the bundled Llama 3.2 local LLM model.
struct LlamaSettingsSection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
                        .fill(statusColor)
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
                .disabled(isBusy)
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

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.bundledLLMStatus {
        case .notDownloaded: return .gray
        case .downloading: return .blue
        case .loading: return .orange
        case .ready: return .green
        case .error: return .red
        }
    }

    private var isBusy: Bool {
        if case .downloading = appState.bundledLLMStatus { return true }
        if case .loading = appState.bundledLLMStatus { return true }
        return false
    }
}
