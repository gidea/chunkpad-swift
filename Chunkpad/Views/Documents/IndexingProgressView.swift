import SwiftUI

struct IndexingProgressView: View {
    let documentName: String
    let progress: Double
    let status: String
    var isModelDownload: Bool = false

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
                    }
                }

                Spacer()

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
