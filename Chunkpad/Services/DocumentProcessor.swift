import Foundation
import PDFKit

// MARK: - Processed Chunk (intermediate)

struct ProcessedChunk: Sendable {
    let title: String
    let content: String
    let documentType: String
    let slideNumber: Int?
    let sourcePath: String
}

// MARK: - Document Processor

/// Parses documents into markdown-formatted text chunks.
/// PDF: PDFKit (page-by-page)
/// DOCX/DOC/RTF/ODT: textutil CLI (macOS)
/// TXT/Markdown: direct read
struct DocumentProcessor: Sendable {

    /// Default chunk size / overlap (characters). Callers should override via parameters.
    static let defaultChunkSizeChars = 4000   // ~1000 tokens × 4
    static let defaultOverlapChars = 400      // ~100 tokens × 4

    // MARK: - Parse File

    /// Process a single file using the appropriate extraction method.
    /// - Parameters:
    ///   - url: Path to the document.
    ///   - chunkSizeChars: Target chunk size in characters. Defaults to 4000 (~1000 tokens).
    ///   - overlapChars: Overlap between consecutive chunks in characters. Defaults to 400 (~100 tokens).
    func processFile(
        at url: URL,
        chunkSizeChars: Int = defaultChunkSizeChars,
        overlapChars: Int = defaultOverlapChars
    ) async throws -> [ProcessedChunk] {
        let ext = url.pathExtension.lowercased()
        let docType = IndexedDocument.DocumentType(fromExtension: ext)

        switch docType {
        case .pdf:
            return try processPDF(at: url, chunkSizeChars: chunkSizeChars, overlapChars: overlapChars)
        case .docx, .doc, .rtf, .odt:
            return try await processViaTextutil(at: url, type: docType, chunkSizeChars: chunkSizeChars, overlapChars: overlapChars)
        case .txt, .markdown:
            return try processPlainText(at: url, type: docType, chunkSizeChars: chunkSizeChars, overlapChars: overlapChars)
        case .unknown:
            throw DocumentProcessorError.unsupportedFormat(ext)
        }
    }

    /// Process all supported files in a directory.
    /// - Parameters:
    ///   - url: Directory path.
    ///   - recursive: Whether to recurse into subdirectories.
    ///   - chunkSizeChars: Target chunk size in characters.
    ///   - overlapChars: Overlap between consecutive chunks in characters.
    func processDirectory(
        at url: URL,
        recursive: Bool = true,
        chunkSizeChars: Int = defaultChunkSizeChars,
        overlapChars: Int = defaultOverlapChars
    ) async throws -> [URL: [ProcessedChunk]] {
        let fm = FileManager.default
        let supportedExtensions = IndexedDocument.DocumentType.supportedExtensions

        var results: [URL: [ProcessedChunk]] = [:]

        // Collect file URLs synchronously to avoid async enumerator issues.
        // Skip the _chunks/ directory to avoid re-processing chunk markdown files.
        let fileURLs: [URL] = {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return [] }

            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                // Skip the _chunks output directory (created by ChunkFileService).
                if fileURL.lastPathComponent == "_chunks" {
                    let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        enumerator.skipDescendants()
                        continue
                    }
                }
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    urls.append(fileURL)
                }
            }
            return urls
        }()

        for fileURL in fileURLs {
            do {
                let chunks = try await processFile(
                    at: fileURL,
                    chunkSizeChars: chunkSizeChars,
                    overlapChars: overlapChars
                )
                if !chunks.isEmpty {
                    results[fileURL] = chunks
                }
            } catch {
                print("Skipping \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - PDF Processing

    private func processPDF(at url: URL, chunkSizeChars: Int, overlapChars: Int) throws -> [ProcessedChunk] {
        guard let document = PDFDocument(url: url) else {
            throw DocumentProcessorError.cannotOpen(url.path)
        }

        var chunks: [ProcessedChunk] = []
        let fileName = url.deletingPathExtension().lastPathComponent

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            // Wrap page text in markdown structure
            let markdown = "# \(fileName) — Page \(pageIndex + 1)\n\n\(text)"

            let pageChunks = splitIntoChunks(
                text: markdown,
                title: "\(fileName) — Page \(pageIndex + 1)",
                documentType: "pdf",
                slideNumber: nil,
                sourcePath: url.path,
                chunkSizeChars: chunkSizeChars,
                overlapChars: overlapChars
            )
            chunks.append(contentsOf: pageChunks)
        }

        return chunks
    }

    // MARK: - textutil Extraction (DOCX, DOC, RTF, ODT)

    /// Extracts text from rich document formats using macOS `textutil` CLI.
    /// Runs `textutil -convert txt -stdout <path>` and captures stdout as UTF-8.
    private func processViaTextutil(
        at url: URL,
        type: IndexedDocument.DocumentType,
        chunkSizeChars: Int,
        overlapChars: Int
    ) async throws -> [ProcessedChunk] {
        let text = try await runTextutil(at: url)
        let fileName = url.deletingPathExtension().lastPathComponent

        // Wrap in markdown structure
        let markdown = "# \(fileName)\n\n\(text)"

        return splitIntoChunks(
            text: markdown,
            title: fileName,
            documentType: type.rawValue,
            slideNumber: nil,
            sourcePath: url.path,
            chunkSizeChars: chunkSizeChars,
            overlapChars: overlapChars
        )
    }

    /// Run `textutil -convert txt -stdout <path>` and return the extracted text.
    private func runTextutil(at url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "txt", "-stdout", url.path]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()  // Discard stderr

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: DocumentProcessorError.cannotOpen(url.path))
                return
            }

            // Must read pipe BEFORE waitUntilExit to avoid deadlock: when the pipe buffer fills,
            // the child blocks on write; we would block on wait; nobody drains the pipe.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                continuation.resume(throwing: DocumentProcessorError.cannotOpen(url.path))
                return
            }
            if let text = String(data: data, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continuation.resume(returning: text)
            } else {
                continuation.resume(throwing: DocumentProcessorError.cannotOpen(url.path))
            }
        }
    }

    // MARK: - Plain Text Processing

    private func processPlainText(
        at url: URL,
        type: IndexedDocument.DocumentType,
        chunkSizeChars: Int,
        overlapChars: Int
    ) throws -> [ProcessedChunk] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let fileName = url.deletingPathExtension().lastPathComponent

        // Wrap in markdown structure
        let markdown = "# \(fileName)\n\n\(text)"

        return splitIntoChunks(
            text: markdown,
            title: fileName,
            documentType: type.rawValue,
            slideNumber: nil,
            sourcePath: url.path,
            chunkSizeChars: chunkSizeChars,
            overlapChars: overlapChars
        )
    }

    // MARK: - Chunking

    /// Split text into overlapping chunks of approximately `chunkSizeChars` characters.
    /// Splits on paragraph boundaries when possible for cleaner chunks.
    private func splitIntoChunks(
        text: String,
        title: String,
        documentType: String,
        slideNumber: Int?,
        sourcePath: String,
        chunkSizeChars: Int,
        overlapChars: Int
    ) -> [ProcessedChunk] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // If text is small enough, return as single chunk
        if cleaned.count <= chunkSizeChars {
            return [ProcessedChunk(
                title: title,
                content: cleaned,
                documentType: documentType,
                slideNumber: slideNumber,
                sourcePath: sourcePath
            )]
        }

        // Split by paragraphs first
        let paragraphs = cleaned.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [ProcessedChunk] = []
        var currentChunk = ""
        var chunkIndex = 0

        for paragraph in paragraphs {
            if currentChunk.count + paragraph.count + 2 > chunkSizeChars && !currentChunk.isEmpty {
                // Emit current chunk
                chunks.append(ProcessedChunk(
                    title: "\(title) [\(chunkIndex + 1)]",
                    content: currentChunk,
                    documentType: documentType,
                    slideNumber: slideNumber,
                    sourcePath: sourcePath
                ))
                chunkIndex += 1

                // Start new chunk with overlap from end of previous
                let overlap = String(currentChunk.suffix(overlapChars))
                currentChunk = overlap + "\n\n" + paragraph
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                currentChunk += paragraph
            }
        }

        // Emit last chunk
        if !currentChunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(ProcessedChunk(
                title: paragraphs.count > 1 ? "\(title) [\(chunkIndex + 1)]" : title,
                content: currentChunk,
                documentType: documentType,
                slideNumber: slideNumber,
                sourcePath: sourcePath
            ))
        }

        return chunks
    }
}

// MARK: - Errors

enum DocumentProcessorError: LocalizedError, Sendable {
    case cannotOpen(String)
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "Cannot open file: \(path)"
        case .unsupportedFormat(let ext): return "Unsupported format: \(ext)"
        }
    }
}
