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
                            Label("Remove Folder…", systemImage: "folder.badge.minus")
                        }

                        Button(role: .destructive) {
                            showClearAllConfirmation = true
                        } label: {
                            Label("Clear All Data…", systemImage: "trash")
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

    private var shouldShowEmptyState: Bool {
        viewModel.chunkFileTree == nil && indexedDocuments.isEmpty && !viewModel.isIndexing
    }

    // MARK: - Collections Section (Tasks 13.6, 13.7)

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                Label("Collections", systemImage: "folder.badge.gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newCollectionName = ""
                    showNewCollectionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("New Collection")
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if viewModel.collections.isEmpty {
                Text("No collections yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            } else {
                ForEach(viewModel.collections) { collection in
                    HStack(spacing: 10) {
                        // Colored indicator dot
                        Circle()
                            .fill(colorFromHex(collection.color) ?? Color.accentColor.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(collection.name)
                            .font(.callout)
                        Spacer()
                        Text("\(collection.documentCount) doc\(collection.documentCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button {
                            renameText = collection.name
                            collectionToRename = collection
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            collectionToDelete = collection
                            showDeleteCollectionConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 4)
        }
    }

    /// Parses a CSS hex color string like `"#FF6B35"` or `"FF6B35"` into a SwiftUI `Color`.
    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        return Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double(value         & 0xFF) / 255
        )
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
                inaccessibleFolderBanner(folder)
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
                errorBanner(error)
                    .padding(.horizontal)
            }

            // 6.3.4: Per-file retry for parse-failed files
            if !viewModel.skippedFiles.isEmpty {
                skippedFilesBanner
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

            collectionsSection

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

    // MARK: - Chunk Tree Sidebar

    private func chunkTreeSidebar(tree: ChunkFileTree) -> some View {
        List(selection: $selectedNodeID) {
            OutlineGroup(tree.rootFolder.children, children: \.children) { node in
                switch node {
                case .folder(let n):
                    // 2.4.3: Per-folder aggregate status badge
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(n.name)
                        Spacer()
                        let status = viewModel.folderAggregateStatus(for: n)
                        Image(systemName: status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(status.dotColor)
                    }
                case .file(let n):
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(n.fileInfo.fileName)
                        Spacer()
                        let status = viewModel.fileAggregateStatus(for: n.fileInfo)
                        Image(systemName: status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(status.dotColor)
                    }
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
        let filtered = filteredChunks(reviewable)
        VStack(spacing: 0) {
            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter chunks...", text: $chunkFilter)
                    .textFieldStyle(.plain)
                if !chunkFilter.isEmpty {
                    Button {
                        chunkFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
            .padding(.horizontal)
            .padding(.top, 8)

            if filtered.isEmpty && !chunkFilter.isEmpty {
                ContentUnavailableView.search(text: chunkFilter)
            } else {
                ScrollView {
                    if chunkViewMode == .grid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 12)], spacing: 12) {
                            ForEach(filtered) { rc in
                                chunkGridCard(reviewable: rc)
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(filtered) { rc in
                                chunkRow(reviewable: rc)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(fileInfo.fileName)
    }

    private func filteredChunks(_ chunks: [ReviewableChunk]) -> [ReviewableChunk] {
        guard !chunkFilter.isEmpty else { return chunks }
        let query = chunkFilter.lowercased()
        return chunks.filter {
            $0.processedChunk.title.lowercased().contains(query) ||
            $0.processedChunk.content.lowercased().contains(query)
        }
    }

    private func chunkRow(reviewable: ReviewableChunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    viewModel.toggleChunkInclusion(id: reviewable.id)
                } label: {
                    Image(systemName: reviewable.embeddingStatus.systemImage)
                        .foregroundStyle(reviewable.embeddingStatus.color)
                }
                .buttonStyle(.plain)

                Text(reviewable.processedChunk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Spacer()

                if reviewable.isIncluded {
                    ChunkStatusBadge(status: reviewable.embeddingStatus, showLabel: true)
                }

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
        .contextMenu {
            Button(role: .destructive) {
                chunkToDelete = reviewable
            } label: {
                Label("Delete Chunk", systemImage: "trash")
            }
            .disabled(viewModel.isIndexing)
        }
    }

    private func chunkGridCard(reviewable: ReviewableChunk) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    viewModel.toggleChunkInclusion(id: reviewable.id)
                } label: {
                    Image(systemName: reviewable.embeddingStatus.systemImage)
                        .foregroundStyle(reviewable.embeddingStatus.color)
                }
                .buttonStyle(.plain)

                Text(reviewable.processedChunk.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Spacer()
            }

            Text(reviewable.processedChunk.content)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(8)

            HStack {
                if reviewable.isIncluded {
                    ChunkStatusBadge(status: reviewable.embeddingStatus, showLabel: false)
                }
                Spacer()
                Text("\(reviewable.processedChunk.content.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(GlassTokens.Padding.element)
        .opacity(reviewable.isIncluded ? 1 : 0.5)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
        .contextMenu {
            Button(role: .destructive) {
                chunkToDelete = reviewable
            } label: {
                Label("Delete Chunk", systemImage: "trash")
            }
            .disabled(viewModel.isIndexing)
        }
    }

    // MARK: - Skipped Files Banner (6.3.4)

    private var skippedFilesBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
                Text("\(viewModel.skippedFiles.count) file\(viewModel.skippedFiles.count == 1 ? "" : "s") could not be parsed")
                    .font(.caption.weight(.semibold))
                Spacer()
            }
            ForEach(viewModel.skippedFiles, id: \.url) { skipped in
                HStack(spacing: 8) {
                    Image(systemName: "doc.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(skipped.url.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(skipped.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Retry") {
                        Task { await viewModel.retrySkippedFile(at: skipped.url) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }

    private func inaccessibleFolderBanner(_ folder: IndexedFolder) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder Not Accessible")
                    .font(.caption.weight(.semibold))
                Text("\(folder.rootURL.lastPathComponent) — access was lost. Re-select to restore or remove it.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-select") {
                Task { await reselectFolder(folder) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button("Remove") {
                showRemoveFolderConfirmation = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(GlassTokens.Padding.element)
        .glassEffect(.regular, in: .rect(cornerRadius: GlassTokens.Radius.element))
    }

    private func errorBanner(_ message: String) -> some View {
        let isEmbeddingError: Bool = {
            if case .error = appState.embeddingModelStatus { return true }
            return false
        }()

        return HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
            Spacer()
            // 6.2: Recovery button when embedding model is in error state
            if isEmbeddingError {
                Button("Clear Cache & Retry") {
                    Task {
                        await viewModel.clearEmbeddingCacheForRecovery()
                        viewModel.error = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
            }
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

    /// Re-selects a folder via NSOpenPanel to restore access (creates new bookmark).
    private func reselectFolder(_ folder: IndexedFolder) async {
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
