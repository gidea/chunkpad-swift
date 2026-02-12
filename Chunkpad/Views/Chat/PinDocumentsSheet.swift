import SwiftUI

/// A sheet that lists all indexed documents and lets the user pin/unpin them.
/// Pinned documents' chunks are always included (boosted) in the next search.
struct PinDocumentsSheet: View {
    let documents: [IndexedDocument]
    let pinnedIDs: Set<String>
    let onToggle: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pin Documents")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            }
            .padding()

            Divider()

            if documents.isEmpty {
                ContentUnavailableView {
                    Label("No Documents", systemImage: "doc.questionmark")
                } description: {
                    Text("Index a folder first to pin documents.")
                }
            } else {
                List(documents) { doc in
                    HStack {
                        Image(systemName: doc.documentType.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.fileName)
                                .font(.body)
                            Text("\(doc.chunkCount) chunks")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button {
                            onToggle(doc.id)
                        } label: {
                            Image(systemName: pinnedIDs.contains(doc.id) ? "pin.fill" : "pin")
                                .foregroundStyle(pinnedIDs.contains(doc.id) ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}
