import SwiftUI

struct IndexingProgressView: View {
    let documentName: String
    let progress: Double
    let status: String
    var isModelDownload: Bool = false
    /// Optional secondary detail line, e.g. "Chunk 14 / 47"
    var detail: String? = nil
    /// Optional cancel action. When non-nil a Cancel button is shown.
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isModelDownload ? "arrow.down.circle" : "doc.text.magnifyingglass")
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(documentName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if isModelDownload {
                        Text("First-time setup: \(EmbeddingService.modelDisplayName) (\(EmbeddingService.modelSize))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(GlassTokens.Padding.card)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.card))
    }
}
