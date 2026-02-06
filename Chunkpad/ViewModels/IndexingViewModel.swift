import SwiftUI

/// Orchestrates the document indexing pipeline:
/// Folder selection → download embedding model (if needed) → parse documents → chunk → embed via MLX → store in SQLite + sqlite-vec.
///
/// The embedding model (bge-base-en-v1.5, ~438 MB) is NOT bundled with the app.
/// It's downloaded from HuggingFace only when the user first triggers indexing.
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

    // MARK: - Dependencies

    private let processor = DocumentProcessor()
    private let embedder = EmbeddingService()
    private let database = DatabaseService()

    /// Optional reference to the shared AppState for updating global embedding status.
    var appState: AppState?

    // MARK: - Index Folder

    /// Opens NSOpenPanel, lets user select a folder, then indexes all supported documents.
    /// Downloads the embedding model on first run if needed.
    func selectAndIndexFolder() async {
        guard !isIndexing else { return }

        // Show folder picker
        guard let folderURL = await pickFolder() else { return }

        await indexFolder(at: folderURL)
    }

    /// Index all documents in a given folder.
    func indexFolder(at url: URL) async {
        isIndexing = true
        error = nil
        progress = 0
        processedFiles = 0

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
            let fileChunks = try await processor.processDirectory(at: url)
            totalFiles = fileChunks.count

            guard totalFiles > 0 else {
                currentDocument = "No supported documents found."
                isIndexing = false
                return
            }

            // 4. Process each file: embed chunks → store
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

                // Store document metadata
                try await database.insertDocument(document)

                // Embed and store each chunk (documents embedded without query prefix)
                for chunk in chunks {
                    let embedding = try await embedder.embed(chunk.content)
                    let chunkModel = Chunk(
                        title: chunk.title,
                        content: chunk.content,
                        documentType: chunk.documentType,
                        slideNumber: chunk.slideNumber,
                        sourcePath: chunk.sourcePath
                    )
                    try await database.insertChunk(chunkModel, documentID: document.id, embedding: embedding)
                }

                processedFiles += 1
                progress = Double(processedFiles) / Double(totalFiles)
            }

            currentDocument = "Done! Indexed \(totalFiles) documents."
        } catch {
            self.error = error.localizedDescription
            currentDocument = "Error: \(error.localizedDescription)"
            isDownloadingModel = false
        }

        isIndexing = false
    }

    // MARK: - Folder Picker

    @MainActor
    private func pickFolder() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select a folder to index"
            panel.prompt = "Index"

            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
