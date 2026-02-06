import SwiftUI

struct DocumentsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = IndexingViewModel()
    @State private var indexedDocuments: [IndexedDocument] = []

    var body: some View {
        Group {
            if indexedDocuments.isEmpty && !viewModel.isIndexing {
                emptyState
            } else {
                documentList
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.selectAndIndexFolder() }
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .disabled(viewModel.isIndexing)
            }
        }
        .onAppear {
            viewModel.appState = appState
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Documents Indexed", systemImage: "doc.on.doc")
        } description: {
            Text("Add a folder to index your documents for search.\nSupported: PDF, DOCX, RTF, TXT, Markdown, PPTX.")
        } actions: {
            Button("Add Folder") {
                Task { await viewModel.selectAndIndexFolder() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        VStack(spacing: 0) {
            // Show model download progress if active
            if viewModel.isDownloadingModel {
                IndexingProgressView(
                    documentName: viewModel.currentDocument,
                    progress: viewModel.modelDownloadProgress,
                    status: "Embedding model",
                    isModelDownload: true
                )
                .padding()

                Divider()
            }

            // Show indexing progress if active (and not downloading model)
            if viewModel.isIndexing && !viewModel.isDownloadingModel {
                IndexingProgressView(
                    documentName: viewModel.currentDocument,
                    progress: viewModel.progress,
                    status: "\(viewModel.processedFiles)/\(viewModel.totalFiles) files",
                    isModelDownload: false
                )
                .padding()

                Divider()
            }

            // Error banner
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                }
                .padding()
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            List(indexedDocuments) { doc in
                HStack(spacing: 12) {
                    Image(systemName: doc.documentType.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.fileName)
                            .font(.body.weight(.medium))

                        Text("\(doc.chunkCount) chunks  ·  \(doc.documentType.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(doc.indexedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
