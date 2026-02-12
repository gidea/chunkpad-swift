import SwiftUI
import AppKit

struct DocumentsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = IndexingViewModel()
    @State private var indexedDocuments: [IndexedDocument] = []
    @State private var selectedNodeID: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.error, shouldShowEmptyState {
                errorBanner(error)
                    .padding()
            }

            if shouldShowEmptyState {
                emptyState
            } else {
                documentList
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await viewModel.selectAndProcessFolder() }
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .disabled(viewModel.isIndexing)
            }
        }
        .onAppear {
            viewModel.appState = appState
        }
        .task {
            await viewModel.loadFromDatabase()
            if viewModel.indexedFolder != nil {
                await viewModel.refreshChunkTree()
            }
            indexedDocuments = await viewModel.loadIndexedDocumentsFromDatabase()
        }
        .onChange(of: viewModel.isIndexing) { _, isActive in
            if !isActive {
                Task { indexedDocuments = await viewModel.loadIndexedDocumentsFromDatabase() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.indexedFolder != nil {
                Task { await viewModel.checkForModifiedChunkFiles() }
            }
        }
    }

    private var shouldShowEmptyState: Bool {
        viewModel.chunkFileTree == nil && indexedDocuments.isEmpty && !viewModel.isIndexing
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Documents Indexed", systemImage: "doc.on.doc")
        } description: {
            Text("Add a folder to process your documents.\nSupported: TXT, RTF, DOC, DOCX, ODT, PDF.")
        } actions: {
            Button("Add Folder") {
                Task { await viewModel.selectAndProcessFolder() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Document List (Tree + Chunk Detail)

    private var documentList: some View {
        VStack(spacing: 0) {
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

            if let error = viewModel.error {
                errorBanner(error)
                    .padding(.horizontal)
            }

            if viewModel.hasModifiedChunkFiles {
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                        .foregroundStyle(.orange)
                    Text("Some chunk files have been modified. Re-embed to update the index.")
                        .font(.caption)
                    Spacer()
                    Button("Re-embed") {
                        Task { await reembedModifiedChunks() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(GlassTokens.Padding.element)
                .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
                .padding(.horizontal)
            }

            if let tree = viewModel.chunkFileTree {
                NavigationSplitView {
                    chunkTreeSidebar(tree: tree)
                } detail: {
                    chunkDetailView(selectedNodeID: selectedNodeID)
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            } else if !indexedDocuments.isEmpty {
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

    // MARK: - Chunk Tree Sidebar

    private func chunkTreeSidebar(tree: ChunkFileTree) -> some View {
        List(selection: $selectedNodeID) {
            OutlineGroup(tree.rootFolder.children, children: \.children) { node in
                switch node {
                case .folder(let n):
                    Label(n.name, systemImage: "folder")
                case .file(let n):
                    Label(n.fileInfo.fileName, systemImage: "doc.text")
                        .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chunk Files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let approved = viewModel.approvedChunksForEmbed().count
                Button("Embed Selected (\(approved))") {
                    Task { await embedApprovedChunks() }
                }
                .disabled(approved == 0 || viewModel.isIndexing)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func chunkDetailView(selectedNodeID: String?) -> some View {
        Group {
            if let id = selectedNodeID, let fileNode = findFileNode(id: id, in: viewModel.chunkFileTree?.rootFolder) {
                chunkListView(for: fileNode.fileInfo)
            } else {
                ContentUnavailableView {
                    Label("Select a File", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Choose a chunk file from the sidebar to view and toggle chunks for embedding.")
                }
            }
        }
    }

    private func findFileNode(id: String, in root: ChunkFolderNode?) -> ChunkFileNode? {
        guard let root else { return nil }
        for child in root.children {
            switch child {
            case .file(let n):
                if child.id == id { return n }
            case .folder(let n):
                if let found = findFileNode(id: id, in: n) { return found }
            }
        }
        return nil
    }

    @ViewBuilder
    private func chunkListView(for fileInfo: ChunkFileInfo) -> some View {
        let reviewable = viewModel.reviewableChunks(for: fileInfo)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(fileInfo.fileName)
                    .font(.title3.weight(.semibold))
                    .padding(.bottom, 4)

                ForEach(reviewable) { rc in
                    chunkRow(reviewable: rc)
                }
            }
            .padding()
        }
        .navigationTitle(fileInfo.fileName)
    }

    private func chunkRow(reviewable: ReviewableChunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    viewModel.toggleChunkInclusion(id: reviewable.id)
                } label: {
                    Image(systemName: reviewable.isIncluded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)

                Text(reviewable.processedChunk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()
                Text("\(reviewable.processedChunk.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(reviewable.processedChunk.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .lineLimit(20)
        }
        .padding(GlassTokens.Padding.element)
        .opacity(reviewable.isIncluded ? 1 : 0.5)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            Button("Dismiss") { viewModel.error = nil }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }

    private func embedApprovedChunks() async {
        let chunks = viewModel.approvedChunksForEmbed()
        await viewModel.embedApprovedChunks(from: chunks)
    }

    private func reembedModifiedChunks() async {
        let chunks = viewModel.approvedChunksForEmbed()
        await viewModel.embedApprovedChunks(from: chunks)
        viewModel.acknowledgeChunkFileModifications()
    }
}
