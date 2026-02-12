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

    // MARK: - Dependencies

    private let processor = DocumentProcessor()
    private let chunkFileService = ChunkFileService()
    private let embedder = EmbeddingService()
    private let database = DatabaseService()

    /// Optional reference to the shared AppState for updating global embedding status
    /// and reading chunking settings.
    var appState: AppState?

    init() {}

    /// Loads indexed folders and embedded chunk IDs from the database. Call from DocumentsView.onAppear.
    func loadFromDatabase() async {
        do {
            try await database.connect()
            indexedFolders = try await database.fetchIndexedFolders()
            embeddedChunkIDs = try await database.fetchEmbeddedChunkRefIds()
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
        guard let folderURL = await pickFolder() else { return }
        await processFolder(at: folderURL)
    }

    /// Extracts text, chunks, writes markdown files to {folder}_chunks/, discovers and builds tree.
    func processFolder(at url: URL) async {
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
            let folder = IndexedFolder(rootURL: rootURL, chunksRootURL: chunksRoot, fileCount: totalFiles, chunkCount: totalChunks)
            try await database.connect()
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
        guard let folderURL = await pickFolder() else { return }

        await indexFolder(at: folderURL)
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
            try await database.connect()

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
            try await database.connect()
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
    func reviewableChunks(for fileInfo: ChunkFileInfo) -> [ReviewableChunk] {
        fileInfo.chunks.enumerated().map { index, pc in
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
            try await database.connect()
            return try await database.listDocuments()
        } catch {
            return []
        }
    }

    // MARK: - Folder Picker

    @MainActor
    private func pickFolder() async -> URL? {
        await withCheckedContinuation { continuation in
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
    }
}
