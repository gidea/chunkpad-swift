import SwiftUI
import AppKit

struct DocumentsView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = IndexingViewModel()
    @State private var indexedDocuments: [IndexedDocument] = []
    @State private var selectedNodeID: String?
    @State private var showRemoveFolderConfirmation = false
    @State private var showClearAllConfirmation = false
    @State private var documentToDelete: IndexedDocument?
    @State private var chunkToDelete: ReviewableChunk?
    @State private var chunkViewMode: ChunkViewMode = {
        if let raw = UserDefaults.standard.string(forKey: "documents_chunk_view_mode"),
           let mode = ChunkViewMode(rawValue: raw) {
            return mode
        }
        return .list
    }()
    @State private var chunkFilter = ""

    // Collection management state (Tasks 13.6, 13.7)
    @State private var showNewCollectionSheet = false
    @State private var newCollectionName = ""
    @State private var collectionToRename: Collection? = nil
    @State private var renameText = ""
    @State private var collectionToDelete: Collection? = nil
    @State private var showDeleteCollectionConfirmation = false
    @State private var showFeedbackManagement = false

    enum ChunkViewMode: String {
        case list, grid
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.error, shouldShowEmptyState {
                DocumentsErrorBanner(
                    message: error,
                    showCacheRecovery: isEmbeddingError,
                    onClearCache: {
                        Task {
                            await viewModel.clearEmbeddingCacheForRecovery()
                            viewModel.error = nil
                        }
                    },
                    onDismiss: { viewModel.error = nil }
                )
                .padding()
            }

            if shouldShowEmptyState {
                emptyState
            } else {
                documentList
            }
        }
        .navigationTitle("Documents")
        .toolbar { toolbarContent }
        .confirmationDialog("Remove Folder", isPresented: $showRemoveFolderConfirmation) {
            Button("Remove from Library", role: .destructive) {
                guard let folder = viewModel.indexedFolder else { return }
                Task { await viewModel.removeFolder(folder, deleteChunkFiles: false) }
            }
            Button("Remove Everything", role: .destructive) {
                guard let folder = viewModel.indexedFolder else { return }
                Task { await viewModel.removeFolder(folder, deleteChunkFiles: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove this folder from Chunkpad? \"Remove Everything\" also deletes the _chunks directory on disk.")
        }
        .confirmationDialog("Clear All Data", isPresented: $showClearAllConfirmation) {
            Button("Clear Database Only", role: .destructive) {
                Task { await viewModel.clearAllData(deleteChunkFiles: false) }
            }
            Button("Clear Everything", role: .destructive) {
                Task { await viewModel.clearAllData(deleteChunkFiles: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete all indexed data? \"Clear Everything\" also removes chunk files from disk.")
        }
        .alert("Delete Document?", isPresented: .init(
            get: { documentToDelete != nil },
            set: { if !$0 { documentToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let doc = documentToDelete {
                    Task {
                        await viewModel.deleteDocument(id: doc.id)
                        indexedDocuments = await viewModel.loadIndexedDocumentsFromDatabase()
                    }
                }
            }
            Button("Cancel", role: .cancel) { documentToDelete = nil }
        } message: {
            Text("This will permanently delete \"\(documentToDelete?.fileName ?? "")\" and all its chunks.")
        }
        .alert("Delete Chunk?", isPresented: .init(
            get: { chunkToDelete != nil },
            set: { if !$0 { chunkToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let chunk = chunkToDelete {
                    Task {
                        await viewModel.deleteChunk(id: chunk.id)
                        await viewModel.refreshChunkTree()
                    }
                }
            }
            Button("Cancel", role: .cancel) { chunkToDelete = nil }
        } message: {
            Text("This will permanently delete this chunk from the database.")
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
            await viewModel.loadCollections()
        }
        .onChange(of: viewModel.isIndexing) { _, isActive in
            if !isActive {
                Task {
                    indexedDocuments = await viewModel.loadIndexedDocumentsFromDatabase()
                    await viewModel.loadCollections()
                }
            }
        }
        .onChange(of: selectedNodeID) { _, _ in chunkFilter = "" }
        // New Collection sheet (Task 13.6)
        .sheet(isPresented: $showNewCollectionSheet) {
            newCollectionSheet
        }
        // Rename Collection alert (Task 13.6)
        .alert("Rename Collection", isPresented: .init(
            get: { collectionToRename != nil },
            set: { if !$0 { collectionToRename = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                guard let c = collectionToRename else { return }
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Task {
                    await viewModel.renameCollection(id: c.id, name: name)
                    collectionToRename = nil
                }
            }
            Button("Cancel", role: .cancel) { collectionToRename = nil }
        } message: {
            if let c = collectionToRename {
                Text("Enter a new name for \u{201C}\(c.name)\u{201D}.")
            }
        }
        // Delete Collection confirmation (Task 13.6)
        .confirmationDialog("Delete \u{201C}\(collectionToDelete?.name ?? "")\u{201D}?", isPresented: $showDeleteCollectionConfirmation, titleVisibility: .visible) {
            Button("Delete Collection", role: .destructive) {
                guard let c = collectionToDelete else { return }
                Task {
                    await viewModel.deleteCollection(id: c.id)
                    collectionToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { collectionToDelete = nil }
        } message: {
            Text("Documents in this collection will become Uncategorized.")
        }
        // Post-embed collection assignment sheet (Task 13.7)
        .sheet(isPresented: $viewModel.showCollectionAssignmentSheet) {
            CollectionAssignmentSheet(
                documentCount: viewModel.lastEmbeddedDocumentIDs.count,
                collections: viewModel.collections,
                onAssign: { collectionId in
                    Task { await viewModel.assignNewlyEmbeddedDocuments(to: collectionId) }
                },
                onSkip: {
                    viewModel.lastEmbeddedDocumentIDs = []
                    viewModel.showCollectionAssignmentSheet = false
                }
            )
        }
        .sheet(isPresented: $showFeedbackManagement) {
            FeedbackManagementView(database: DatabaseService())
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if viewModel.indexedFolder != nil {
                Task { await viewModel.checkForModifiedChunkFiles() }
            }
        }
    }

    // MARK: - Computed Properties

    private var shouldShowEmptyState: Bool {
        viewModel.chunkFileTree == nil && indexedDocuments.isEmpty && !viewModel.isIndexing
    }

    private var isEmbeddingError: Bool {
        if case .error = appState.embeddingModelStatus { return true }
        return false
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await viewModel.selectAndProcessFolder() }
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .disabled(viewModel.isIndexing)
        }
        if viewModel.chunkFileTree != nil {
            ToolbarItem {
                Picker("View", selection: $chunkViewMode) {
                    Image(systemName: "list.bullet")
                        .tag(ChunkViewMode.list)
                    Image(systemName: "square.grid.2x2")
                        .tag(ChunkViewMode.grid)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
                .onChange(of: chunkViewMode) { _, newMode in
                    UserDefaults.standard.set(newMode.rawValue, forKey: "documents_chunk_view_mode")
                }
            }
        }
        if viewModel.indexedFolder != nil {
            ToolbarItem {
                Menu {
                    Button {
                        guard let folder = viewModel.indexedFolder else { return }
                        Task { await viewModel.reprocessFolder(folder) }
                    } label: {
                        Label("Re-process Folder", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isIndexing)

                    Button {
                        Task { await viewModel.reembedAllChunks() }
                    } label: {
                        Label("Re-embed All Chunks", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isIndexing)

                    Divider()

                    Button(role: .destructive) {
                        showRemoveFolderConfirmation = true
                    } label: {
                        Label("Remove Folder\u{2026}", systemImage: "folder.badge.minus")
                    }

                    Button(role: .destructive) {
                        showClearAllConfirmation = true
                    } label: {
                        Label("Clear All Data\u{2026}", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showFeedbackManagement = true
            } label: {
                Label("Chunk Feedback", systemImage: "hand.thumbsup.circle")
            }
        }
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
            if let folder = viewModel.indexedFolder, !folder.isAccessible {
                InaccessibleFolderBanner(
                    folder: folder,
                    onReselect: { Task { await reselectFolder(folder) } },
                    onRemove: { showRemoveFolderConfirmation = true }
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

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
                DocumentsErrorBanner(
                    message: error,
                    showCacheRecovery: isEmbeddingError,
                    onClearCache: {
                        Task {
                            await viewModel.clearEmbeddingCacheForRecovery()
                            viewModel.error = nil
                        }
                    },
                    onDismiss: { viewModel.error = nil }
                )
                .padding(.horizontal)
            }

            // Per-file retry for parse-failed files
            if !viewModel.skippedFiles.isEmpty {
                SkippedFilesBanner(
                    files: viewModel.skippedFiles,
                    onRetry: { url in Task { await viewModel.retrySkippedFile(at: url) } }
                )
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

            CollectionsSectionView(
                collections: viewModel.collections,
                onCreateNew: {
                    newCollectionName = ""
                    showNewCollectionSheet = true
                },
                onRename: { collection in
                    renameText = collection.name
                    collectionToRename = collection
                },
                onDelete: { collection in
                    collectionToDelete = collection
                    showDeleteCollectionConfirmation = true
                }
            )

            if let tree = viewModel.chunkFileTree {
                NavigationSplitView {
                    ChunkTreeSidebarView(
                        tree: tree,
                        selectedNodeID: $selectedNodeID,
                        viewModel: viewModel,
                        onEmbedApproved: { Task { await embedApprovedChunks() } }
                    )
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
                            Text("\(doc.chunkCount) chunks  \u{00B7}  \(doc.documentType.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(doc.indexedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        if !viewModel.collections.isEmpty {
                            Menu {
                                Button("Uncategorized") {
                                    Task { await viewModel.assignDocumentToCollection(documentId: doc.id, collectionId: nil) }
                                }
                                Divider()
                                ForEach(viewModel.collections) { collection in
                                    Button(collection.name) {
                                        Task { await viewModel.assignDocumentToCollection(documentId: doc.id, collectionId: collection.id) }
                                    }
                                }
                            } label: {
                                Label("Move to Collection", systemImage: "folder")
                            }
                            Divider()
                        }
                        Button(role: .destructive) {
                            documentToDelete = doc
                        } label: {
                            Label("Delete Document", systemImage: "trash")
                        }
                        .disabled(viewModel.isIndexing)
                    }
                }
            }
        }
    }

    // MARK: - Chunk Detail

    private func chunkDetailView(selectedNodeID: String?) -> some View {
        Group {
            if let id = selectedNodeID, let fileNode = findFileNode(id: id, in: viewModel.chunkFileTree?.rootFolder) {
                ChunkListView(
                    fileInfo: fileNode.fileInfo,
                    reviewableChunks: viewModel.reviewableChunks(for: fileNode.fileInfo),
                    viewMode: chunkViewMode,
                    filter: $chunkFilter,
                    onToggleInclusion: { id in viewModel.toggleChunkInclusion(id: id) },
                    onDelete: { rc in chunkToDelete = rc },
                    isIndexing: viewModel.isIndexing
                )
            } else {
                ContentUnavailableView {
                    Label("Select a File", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("Choose a chunk file from the sidebar to view and toggle chunks for embedding.")
                }
            }
        }
    }

    // MARK: - New Collection Sheet

    private var newCollectionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Collection Name", text: $newCollectionName)
                } footer: {
                    Text("Give this group of documents a meaningful name.")
                }
            }
            .navigationTitle("New Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showNewCollectionSheet = false
                        newCollectionName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.createCollection(name: name)
                            showNewCollectionSheet = false
                            newCollectionName = ""
                        }
                    }
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 180)
    }
}

// MARK: - Actions

private extension DocumentsView {
    func findFileNode(id: String, in root: ChunkFolderNode?) -> ChunkFileNode? {
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

    func embedApprovedChunks() async {
        let chunks = viewModel.approvedChunksForEmbed()
        await viewModel.embedApprovedChunks(from: chunks)
    }

    func reembedModifiedChunks() async {
        let chunks = viewModel.approvedChunksForEmbed()
        await viewModel.embedApprovedChunks(from: chunks)
        viewModel.acknowledgeChunkFileModifications()
    }

    func reselectFolder(_ folder: IndexedFolder) async {
        await viewModel.reprocessFolder(folder)
    }
}

// MARK: - Collection Assignment Sheet (Task 13.7)

/// Presented after embedding completes to let the user bulk-assign newly indexed
/// documents to a collection. Skipping leaves them uncategorized.
private struct CollectionAssignmentSheet: View {
    let documentCount: Int
    let collections: [Collection]
    let onAssign: (String?) -> Void
    let onSkip: () -> Void

    @State private var selectedCollectionId: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Assign to Collection?")
                    .font(.headline)
                Text("\(documentCount) document\(documentCount == 1 ? "" : "s") were indexed. Assign them to a collection to scope chat searches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("Collection", selection: $selectedCollectionId) {
                Text("Uncategorized").tag(String?.none)
                Divider()
                ForEach(collections) { collection in
                    Text(collection.name).tag(Optional(collection.id))
                }
            }
            .pickerStyle(.radioGroup)

            HStack {
                Button("Skip") { onSkip() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Assign") { onAssign(selectedCollectionId) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 400, minHeight: 220)
    }
}
