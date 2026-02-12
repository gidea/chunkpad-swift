import SwiftUI

/// Result of a processing-only run (no embeddings, no DB).
/// Groups processed chunks by their source file URL.
struct ProcessingResult: Identifiable {
    let id = UUID()
    let fileURL: URL
    let chunks: [ProcessedChunk]

    var fileName: String { fileURL.lastPathComponent }
}


/// Orchestrates the document indexing pipeline:
/// Folder selection → download embedding model (if needed) → parse documents → chunk → embed via MLX → store in SQLite + sqlite-vec.
///
/// Also supports a **processing-only** pipeline that extracts and chunks documents
/// without downloading the embedding model or writing to the database — useful for
/// verifying extraction and chunking before re-enabling full indexing.
///
/// The embedding model (bge-base-en-v1.5, ~438 MB) is NOT bundled with the app.
/// It's downloaded automatically only when the user first triggers indexing.
@Observable
@MainActor
final class IndexingViewModel {

    // MARK: - State

    var isIndexing = false
    var isDownloadingModel = false
    var modelDownloadProgress: Double = 0
    var currentDocument: String = ""
    var progress: Double = 0
    var totalFiles: Int = 0
    var processedFiles: Int = 0
    var error: String?

    // MARK: - Processing-Only Results

    /// Results from the most recent processing-only run, for preview / verification.
    var lastProcessedResults: [ProcessingResult] = []
    /// Total number of chunks across all files in the last processing-only run.
    var lastProcessedTotalChunks: Int = 0
    /// Whether the chunk preview sheet is visible.
    var showChunkPreview = false

    // MARK: - Chunk Files (Markdown on Disk)

    /// Indexed folders (loaded from DB). For MVP, we use the first as the active folder.
    var indexedFolders: [IndexedFolder] = []
    /// The active indexed folder (first in list for MVP).
    var indexedFolder: IndexedFolder? { indexedFolders.first }
    /// Tree of chunk markdown files, built from disk.
    var chunkFileTree: ChunkFileTree?
    /// IDs of chunks that have been embedded into the vector DB. Loaded from DB.
    var embeddedChunkIDs: Set<String> = []
    /// Modified chunk file URLs (for change detection). Key: file path, value: last known modification date.
    var lastKnownModificationDates: [String: Date] = [:]
    /// Whether modified chunk files have been detected (prompt user to re-embed).
    var hasModifiedChunkFiles = false
    /// User toggles for include/exclude. Nil = use default (embedded means included, else true).
    var chunkInclusionOverrides: [String: Bool] = [:]
    /// Cache for reviewableChunks keyed by file path. Invalidated when embeddedChunkIDs or overrides change.
    private var reviewableChunksCache: [String: [ReviewableChunk]] = [:]
    /// Snapshot of embeddedChunkIDs count when cache was last valid.
    private var cachedEmbeddedIDsCount = 0
    /// Snapshot of overrides count when cache was last valid.
    private var cachedOverridesCount = 0

    // MARK: - Dependencies

    private let processor = DocumentProcessor()
    private let chunkFileService = ChunkFileService()
    private let embedder = EmbeddingService()
    private let database = DatabaseService()
    private let bookmarkService = BookmarkService()

    /// Whether the database has been connected at least once this session.
    private var isDatabaseConnected = false

    /// URLs currently under security-scoped access (need stopAccessing on cleanup).
    private var accessedURLs: Set<URL> = []

    /// Optional reference to the shared AppState for updating global embedding status
    /// and reading chunking settings.
    var appState: AppState?

    init() {}

    /// Connects to the database if not already connected this session.
    /// Avoids repeated actor hops when the connection is already established.
    private func ensureDatabaseConnected() async throws {
        if !isDatabaseConnected {
            try await database.connect()
            isDatabaseConnected = true
        }
    }

    /// Loads indexed folders and embedded chunk IDs from the database. Call from DocumentsView.onAppear.
    /// Resolves security-scoped bookmarks and starts access for each folder.
    func loadFromDatabase() async {
        do {
            try await ensureDatabaseConnected()
            var folders = try await database.fetchIndexedFolders()
            embeddedChunkIDs = try await database.fetchEmbeddedChunkRefIds()

            // Resolve bookmarks and start security-scoped access
            for i in folders.indices {
                guard let bookmarkData = folders[i].bookmarkData else {
                    folders[i].isAccessible = false
                    continue
                }
                do {
                    let (url, refreshedBookmark) = try bookmarkService.resolveAndAccess(bookmarkData)
                    accessedURLs.insert(url)
                    folders[i].isAccessible = true
                    // Update URL if it changed (e.g. folder was moved)
                    let resolvedStd = url.standardized
                    let folderStd = folders[i].rootURL.standardized
                    if resolvedStd != folderStd {
                        folders[i] = IndexedFolder(
                            rootURL: url,
                            chunksRootURL: folders[i].chunksRootURL,
                            id: folders[i].id,
                            createdAt: folders[i].createdAt,
                            lastProcessedAt: folders[i].lastProcessedAt,
                            fileCount: folders[i].fileCount,
                            chunkCount: folders[i].chunkCount,
                            bookmarkData: refreshedBookmark ?? bookmarkData
                        )
                    }
                    // Refresh stale bookmark in DB
                    if let refreshed = refreshedBookmark, let folderId = folders[i].id {
                        try? await database.updateFolderBookmark(id: folderId, bookmarkData: refreshed)
                        folders[i].bookmarkData = refreshed
                    }
                } catch {
                    folders[i].isAccessible = false
                    print("Bookmark resolution failed for \(folders[i].rootURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            indexedFolders = folders
        } catch {
            indexedFolders = []
            embeddedChunkIDs = []
        }
    }

    // MARK: - Process Folder (Extract → Write Chunks → Build Tree)

    /// Opens NSOpenPanel, lets user select a folder, then runs the processing-only pipeline:
    /// discover files → extract text → build markdown → chunk. No embeddings, no DB.
    func selectAndProcessFolder() async {
        guard !isIndexing else { return }
        guard let result = await pickFolder() else { return }
        await processFolder(at: result.url, bookmarkData: result.bookmarkData)
    }

    /// Extracts text, chunks, writes markdown files to {folder}_chunks/, discovers and builds tree.
    func processFolder(at url: URL, bookmarkData: Data? = nil) async {
        isIndexing = true
        error = nil
        progress = 0
        processedFiles = 0
        totalFiles = 0
        lastProcessedResults = []
        lastProcessedTotalChunks = 0
        chunkFileTree = nil

        let chunkSizeChars = appState?.chunkSizeChars ?? DocumentProcessor.defaultChunkSizeChars
        let overlapChars = appState?.chunkOverlapChars ?? DocumentProcessor.defaultOverlapChars
        let rootURL = url.standardized

        do {
            currentDocument = "Scanning folder..."

            let fileChunks = try await processor.processDirectory(
                at: rootURL,
                chunkSizeChars: chunkSizeChars,
                overlapChars: overlapChars
            )

            totalFiles = fileChunks.count

            guard totalFiles > 0 else {
                currentDocument = "No supported documents found."
                isIndexing = false
                return
            }

            // Write chunk markdown files to {root}_chunks/
            var totalChunks = 0
            var fileIndex = 0
            for (fileURL, chunks) in fileChunks.sorted(by: { $0.key.lastPathComponent < $1.key.lastPathComponent }) {
                currentDocument = fileURL.lastPathComponent
                _ = try chunkFileService.writeChunks(chunks, sourceFileURL: fileURL, rootFolderURL: rootURL)
                totalChunks += chunks.count
                fileIndex += 1
                processedFiles = fileIndex
                progress = Double(fileIndex) / Double(totalFiles)
            }

            // Discover chunk files and build tree
            let chunksRoot = chunkFileService.chunksRootURL(for: rootURL)
            let chunkFiles = try chunkFileService.discoverChunkFiles(in: chunksRoot)
            for info in chunkFiles {
                lastKnownModificationDates[info.fileURL.path] = info.lastModified
            }
            chunkFileTree = ChunkFileTree(chunkFiles: chunkFiles, chunksRootURL: chunksRoot)
            let folder = IndexedFolder(rootURL: rootURL, chunksRootURL: chunksRoot, fileCount: totalFiles, chunkCount: totalChunks, bookmarkData: bookmarkData)
            try await ensureDatabaseConnected()
            try await database.insertIndexedFolder(folder, fileCount: totalFiles, chunkCount: totalChunks)
            indexedFolders = try await database.fetchIndexedFolders()

            lastProcessedResults = fileChunks.sorted(by: { $0.key.lastPathComponent < $1.key.lastPathComponent }).map { fileURL, chunks in
                ProcessingResult(fileURL: fileURL, chunks: chunks)
            }
            lastProcessedTotalChunks = totalChunks
            currentDocument = "Done! Processed \(totalFiles) files, \(totalChunks) chunks."
        } catch {
            self.error = error.localizedDescription
            currentDocument = "Error: \(error.localizedDescription)"
        }

        isIndexing = false
    }

    // MARK: - Index Folder (Full Pipeline — Embed + DB)

    /// Opens NSOpenPanel, lets user select a folder, then indexes all supported documents.
    /// Downloads the embedding model on first run if needed.
    func selectAndIndexFolder() async {
        guard !isIndexing else { return }

        // Show folder picker
        guard let result = await pickFolder() else { return }

        await indexFolder(at: result.url)
    }

    /// Index all documents in a given folder (full pipeline: embed + DB).
    func indexFolder(at url: URL) async {
        isIndexing = true
        error = nil
        progress = 0
        processedFiles = 0

        let chunkSizeChars = appState?.chunkSizeChars ?? DocumentProcessor.defaultChunkSizeChars
        let overlapChars = appState?.chunkOverlapChars ?? DocumentProcessor.defaultOverlapChars

        do {
            // 1. Connect to database
            try await ensureDatabaseConnected()

            // 2. Download & load embedding model (lazy — only downloads if not cached)
            currentDocument = "Preparing embedding model..."
            isDownloadingModel = true

            // Set up status callback to bridge actor → MainActor
            await embedder.setStatusCallback { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState?.embeddingModelStatus = status

                    if case .downloading(let p) = status {
                        self.modelDownloadProgress = p
                        self.currentDocument = "Downloading embedding model... \(Int(p * 100))%"
                    } else if case .loading = status {
                        self.currentDocument = "Loading embedding model into memory..."
                    }
                }
            }

            try await embedder.ensureModelReady()
            isDownloadingModel = false

            // 3. Discover & parse all documents in the folder
            currentDocument = "Scanning folder..."
            let fileChunks = try await processor.processDirectory(
                at: url,
                chunkSizeChars: chunkSizeChars,
                overlapChars: overlapChars
            )
            totalFiles = fileChunks.count

            guard totalFiles > 0 else {
                currentDocument = "No supported documents found."
                isIndexing = false
                return
            }

            // 4. Process each file: embed all chunks, then insert document + chunks atomically
            for (fileURL, chunks) in fileChunks {
                currentDocument = fileURL.lastPathComponent
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0

                let docType = IndexedDocument.DocumentType(fromExtension: fileURL.pathExtension)
                let document = IndexedDocument(
                    fileName: fileURL.lastPathComponent,
                    filePath: fileURL.path,
                    documentType: docType,
                    chunkCount: chunks.count,
                    fileSize: fileSize
                )

                var chunksWithEmbeddings: [(Chunk, [Float])] = []
                for chunk in chunks {
                    let embedding = try await embedder.embed(chunk.content)
                    let chunkModel = Chunk(
                        title: chunk.title,
                        content: chunk.content,
                        documentType: chunk.documentType,
                        slideNumber: chunk.slideNumber,
                        sourcePath: chunk.sourcePath
                    )
                    chunksWithEmbeddings.append((chunkModel, embedding))
                }
                try await database.insertDocumentWithChunks(document: document, chunksWithEmbeddings: chunksWithEmbeddings)

                processedFiles += 1
                progress = Double(processedFiles) / Double(totalFiles)
            }

            currentDocument = "Done! Indexed \(totalFiles) documents."

            // Update global document count so ChatViewModel knows documents are available
            if let appState {
                appState.indexedDocumentCount = (appState.indexedDocumentCount) + totalFiles
            }
        } catch {
            self.error = error.localizedDescription
            currentDocument = "Error: \(error.localizedDescription)"
            isDownloadingModel = false
        }

        isIndexing = false
    }

    // MARK: - Embed Chunks

    func embedApprovedChunks(from reviewableChunks: [ReviewableChunk]) async {
        let toEmbed = reviewableChunks.filter { $0.isIncluded }
        guard !toEmbed.isEmpty, !isIndexing else { return }
        isIndexing = true
        error = nil
        isDownloadingModel = false
        do {
            try await ensureDatabaseConnected()
            currentDocument = "Preparing embedding model..."
            isDownloadingModel = true
            await embedder.setStatusCallback { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.appState?.embeddingModelStatus = status
                    if case .downloading(let p) = status {
                        self.modelDownloadProgress = p
                        self.currentDocument = "Downloading embedding model... \(Int(p * 100))%"
                    } else if case .loading = status {
                        self.currentDocument = "Loading embedding model..."
                    }
                }
            }
            try await embedder.ensureModelReady()
            isDownloadingModel = false
            var bySource: [String: [ReviewableChunk]] = [:]
            for rc in toEmbed { bySource[rc.processedChunk.sourcePath, default: []].append(rc) }
            processedFiles = 0
            totalFiles = bySource.count
            let now = Date()
            for (sourcePath, chunks) in bySource {
                currentDocument = (sourcePath as NSString).lastPathComponent
                try await database.deleteDocumentByFilePath(sourcePath)
                if let folder = indexedFolder {
                    let chunkFileURL = chunkFileService.chunkFileURL(for: URL(fileURLWithPath: sourcePath), rootFolderURL: folder.rootURL)
                    try await database.deleteEmbeddedChunkRefs(matchingPrefix: "\(chunkFileURL.path)::")
                }
                let docType = IndexedDocument.DocumentType(fromExtension: (sourcePath as NSString).pathExtension)
                let document = IndexedDocument(id: sourcePath, fileName: (sourcePath as NSString).lastPathComponent, filePath: sourcePath, documentType: docType, chunkCount: chunks.count, fileSize: 0)
                var chunksWithEmbeddings: [(Chunk, [Float])] = []
                for rc in chunks {
                    let embedding = try await embedder.embed(rc.processedChunk.content)
                    let chunkModel = Chunk(title: rc.processedChunk.title, content: rc.processedChunk.content, documentType: rc.processedChunk.documentType, slideNumber: rc.processedChunk.slideNumber, sourcePath: rc.processedChunk.sourcePath)
                    chunksWithEmbeddings.append((chunkModel, embedding))
                }
                try await database.insertDocumentWithChunks(document: document, chunksWithEmbeddings: chunksWithEmbeddings)
                for rc in chunks {
                    try await database.insertEmbeddedChunkRef(chunkRefId: rc.id, chunkId: nil, embeddedAt: now)
                }
                embeddedChunkIDs = try await database.fetchEmbeddedChunkRefIds()
                processedFiles += 1
                progress = Double(processedFiles) / Double(totalFiles)
            }
            currentDocument = "Done! Embedded \(toEmbed.count) chunks."
            if let appState { appState.indexedDocumentCount = (try? await database.documentCount()) ?? appState.indexedDocumentCount }
        } catch {
            self.error = error.localizedDescription
            currentDocument = "Error: \(error.localizedDescription)"
            isDownloadingModel = false
        }
        isIndexing = false
    }

    func refreshChunkTree() async {
        guard let folder = indexedFolder else { return }
        do {
            let chunkFiles = try chunkFileService.discoverChunkFiles(in: folder.chunksRootURL)
            for info in chunkFiles { lastKnownModificationDates[info.fileURL.path] = info.lastModified }
            chunkFileTree = ChunkFileTree(chunkFiles: chunkFiles, chunksRootURL: folder.chunksRootURL)
        } catch { self.error = error.localizedDescription }
    }

    func checkForModifiedChunkFiles() async {
        guard let folder = indexedFolder else { return }
        do {
            let chunkFiles = try chunkFileService.discoverChunkFiles(in: folder.chunksRootURL)
            hasModifiedChunkFiles = chunkFiles.contains { info in
                (lastKnownModificationDates[info.fileURL.path]).map { info.lastModified > $0 } ?? false
            }
        } catch { hasModifiedChunkFiles = false }
    }

    func acknowledgeChunkFileModifications() {
        guard let folder = indexedFolder else { return }
        if let chunkFiles = try? chunkFileService.discoverChunkFiles(in: folder.chunksRootURL) {
            for info in chunkFiles { lastKnownModificationDates[info.fileURL.path] = info.lastModified }
        }
        hasModifiedChunkFiles = false
    }

    /// Builds ReviewableChunks for a file; computes embeddingStatus from embeddedChunkIDs and inclusion state.
    /// Results are memoized and invalidated when embeddedChunkIDs or chunkInclusionOverrides change.
    func reviewableChunks(for fileInfo: ChunkFileInfo) -> [ReviewableChunk] {
        // Invalidate cache when underlying data changes
        if embeddedChunkIDs.count != cachedEmbeddedIDsCount || chunkInclusionOverrides.count != cachedOverridesCount {
            reviewableChunksCache.removeAll()
            cachedEmbeddedIDsCount = embeddedChunkIDs.count
            cachedOverridesCount = chunkInclusionOverrides.count
        }

        let cacheKey = fileInfo.fileURL.path
        if let cached = reviewableChunksCache[cacheKey] {
            return cached
        }

        let result = fileInfo.chunks.enumerated().map { index, pc in
            let id = ReviewableChunk.chunkID(filePath: fileInfo.fileURL.path, index: index)
            let isIncluded = chunkInclusionOverrides[id] ?? true
            let status: ChunkEmbeddingStatus
            if !isIncluded {
                status = .excluded
            } else if embeddedChunkIDs.contains(id) {
                status = .embedded
            } else {
                status = .pending
            }
            return ReviewableChunk(id: id, processedChunk: pc, isIncluded: isIncluded, embeddingStatus: status)
        }
        reviewableChunksCache[cacheKey] = result
        return result
    }

    /// Computes aggregate embedding status for a file's chunks.
    func fileAggregateStatus(for fileInfo: ChunkFileInfo) -> FileEmbeddingStatus {
        let chunks = reviewableChunks(for: fileInfo)
        let included = chunks.filter { $0.isIncluded }
        guard !included.isEmpty else { return .noneEmbedded }

        let embeddedCount = included.filter { $0.embeddingStatus == .embedded }.count
        if embeddedCount == included.count {
            return .allEmbedded
        } else if embeddedCount > 0 {
            return .partiallyEmbedded
        } else {
            return .noneEmbedded
        }
    }

    func toggleChunkInclusion(id: String) {
        let current = chunkInclusionOverrides[id] ?? true
        chunkInclusionOverrides[id] = !current
        // Invalidate memoized reviewable chunks
        reviewableChunksCache.removeAll()
    }

    /// All reviewable chunks from the tree for Embed action; only returns those with isIncluded.
    func approvedChunksForEmbed() -> [ReviewableChunk] {
        guard let tree = chunkFileTree else { return [] }
        var result: [ReviewableChunk] = []
        collectReviewableChunks(from: tree.rootFolder, into: &result)
        return result.filter { $0.isIncluded }
    }

    private func collectReviewableChunks(from node: ChunkFolderNode, into result: inout [ReviewableChunk]) {
        for child in node.children {
            switch child {
            case .file(let fileNode):
                result.append(contentsOf: reviewableChunks(for: fileNode.fileInfo))
            case .folder(let folderNode):
                collectReviewableChunks(from: folderNode, into: &result)
            }
        }
    }

    // MARK: - Load Indexed Documents (for Documents list)

    /// Loads the list of indexed documents from the database (for the Documents tab list).
    /// Returns an empty array if the database is not connected or the query fails.
    func loadIndexedDocumentsFromDatabase() async -> [IndexedDocument] {
        do {
            try await ensureDatabaseConnected()
            return try await database.listDocuments()
        } catch {
            return []
        }
    }

    // MARK: - Folder Lifecycle

    /// Removes a folder and all its associated data from the database.
    /// Optionally deletes chunk files from disk.
    func removeFolder(_ folder: IndexedFolder, deleteChunkFiles: Bool) async {
        guard let folderId = folder.id else { return }
        do {
            try await ensureDatabaseConnected()
            try await database.deleteIndexedFolderCascade(id: folderId, rootPath: folder.rootURL.path)

            if deleteChunkFiles {
                chunkFileService.deleteChunksDirectory(for: folder.rootURL)
            }

            // Stop security-scoped access
            if accessedURLs.contains(folder.rootURL) {
                bookmarkService.stopAccessing(url: folder.rootURL)
                accessedURLs.remove(folder.rootURL)
            }

            // Reset state
            indexedFolders.removeAll { $0.id == folderId }
            if indexedFolder == nil {
                chunkFileTree = nil
                lastKnownModificationDates = [:]
                chunkInclusionOverrides = [:]
                hasModifiedChunkFiles = false
            }

            // Update global count
            if let appState {
                appState.indexedDocumentCount = (try? await database.documentCount()) ?? 0
            }
            embeddedChunkIDs = (try? await database.fetchEmbeddedChunkRefIds()) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-processes an existing folder (re-extract, re-chunk, rebuild tree).
    func reprocessFolder(_ folder: IndexedFolder) async {
        await processFolder(at: folder.rootURL, bookmarkData: folder.bookmarkData)
    }

    /// Re-embeds all approved chunks from the current tree.
    func reembedAllChunks() async {
        let chunks = approvedChunksForEmbed()
        guard !chunks.isEmpty else { return }
        await embedApprovedChunks(from: chunks)
    }

    /// Deletes all data from all tables. Optionally deletes chunk files from disk.
    func clearAllData(deleteChunkFiles: Bool) async {
        do {
            try await ensureDatabaseConnected()

            if deleteChunkFiles {
                for folder in indexedFolders {
                    chunkFileService.deleteChunksDirectory(for: folder.rootURL)
                }
            }

            try await database.deleteAllData()
            stopAllAccess()

            indexedFolders = []
            chunkFileTree = nil
            lastKnownModificationDates = [:]
            chunkInclusionOverrides = [:]
            hasModifiedChunkFiles = false
            embeddedChunkIDs = []

            if let appState {
                appState.indexedDocumentCount = 0
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops security-scoped access for all tracked URLs. Call on app termination.
    func stopAllAccess() {
        for url in accessedURLs {
            bookmarkService.stopAccessing(url: url)
        }
        accessedURLs.removeAll()
    }

    // MARK: - Folder Picker

    @MainActor
    private func pickFolder() async -> (url: URL, bookmarkData: Data?)? {
        let result = await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a folder to process"
            panel.prompt = "Process"

            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }

        guard let url = result else { return nil }

        // Create security-scoped bookmark while we still have NSOpenPanel access
        let bookmarkData = try? bookmarkService.createBookmark(for: url)
        return (url, bookmarkData)
    }
}
