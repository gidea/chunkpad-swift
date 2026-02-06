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

/// Parses documents into text chunks using macOS native APIs.
/// PDF: PDFKit (page-by-page)
/// DOCX/RTF/ODT: textutil via NSAttributedString
/// TXT/Markdown: direct read
struct DocumentProcessor: Sendable {

    /// Target chunk size in characters (~500 tokens ≈ 2000 chars).
    /// Chunks overlap by ~10% for context continuity.
    static let targetChunkSize = 2000
    static let overlapSize = 200

    // MARK: - Parse File

    func processFile(at url: URL) async throws -> [ProcessedChunk] {
        let ext = url.pathExtension.lowercased()
        let docType = IndexedDocument.DocumentType(fromExtension: ext)

        switch docType {
        case .pdf:
            return try processPDF(at: url)
        case .docx, .rtf:
            return try processRichText(at: url, type: docType)
        case .txt, .markdown:
            return try processPlainText(at: url, type: docType)
        case .pptx:
            // PPTX requires more complex parsing; for now treat as rich text via textutil
            return try processRichText(at: url, type: docType)
        case .unknown:
            // Attempt plain text
            return try processPlainText(at: url, type: .txt)
        }
    }

    /// Process all supported files in a directory (non-recursive or recursive).
    func processDirectory(at url: URL, recursive: Bool = true) async throws -> [URL: [ProcessedChunk]] {
        let fm = FileManager.default
        let supportedExtensions = Set(["pdf", "docx", "doc", "rtf", "txt", "text", "md", "markdown", "pptx", "ppt"])

        var results: [URL: [ProcessedChunk]] = [:]

        // Collect file URLs synchronously to avoid async enumerator issues
        let fileURLs: [URL] = {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { return [] }

            var urls: [URL] = []
            for case let fileURL as URL in enumerator {
                if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    urls.append(fileURL)
                }
            }
            return urls
        }()

        for fileURL in fileURLs {
            do {
                let chunks = try await processFile(at: fileURL)
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

    private func processPDF(at url: URL) throws -> [ProcessedChunk] {
        guard let document = PDFDocument(url: url) else {
            throw DocumentProcessorError.cannotOpen(url.path)
        }

        var chunks: [ProcessedChunk] = []
        let fileName = url.deletingPathExtension().lastPathComponent

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let pageChunks = splitIntoChunks(
                text: text,
                title: "\(fileName) — Page \(pageIndex + 1)",
                documentType: "pdf",
                slideNumber: nil,
                sourcePath: url.path
            )
            chunks.append(contentsOf: pageChunks)
        }

        return chunks
    }

    // MARK: - Rich Text Processing (DOCX, RTF via NSAttributedString)

    private func processRichText(at url: URL, type: IndexedDocument.DocumentType) throws -> [ProcessedChunk] {
        let data = try Data(contentsOf: url)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any]

        switch type {
        case .docx:
            options = [.documentType: NSAttributedString.DocumentType.docFormat]
        case .rtf:
            options = [.documentType: NSAttributedString.DocumentType.rtf]
        default:
            options = [:]
        }

        let attributed = try NSAttributedString(data: data, options: options, documentAttributes: nil)
        let text = attributed.string
        let fileName = url.deletingPathExtension().lastPathComponent

        return splitIntoChunks(
            text: text,
            title: fileName,
            documentType: type.rawValue,
            slideNumber: nil,
            sourcePath: url.path
        )
    }

    // MARK: - Plain Text Processing

    private func processPlainText(at url: URL, type: IndexedDocument.DocumentType) throws -> [ProcessedChunk] {
        let text = try String(contentsOf: url, encoding: .utf8)
        let fileName = url.deletingPathExtension().lastPathComponent

        return splitIntoChunks(
            text: text,
            title: fileName,
            documentType: type.rawValue,
            slideNumber: nil,
            sourcePath: url.path
        )
    }

    // MARK: - Chunking

    /// Split text into overlapping chunks of approximately `targetChunkSize` characters.
    /// Splits on paragraph boundaries when possible for cleaner chunks.
    private func splitIntoChunks(text: String, title: String, documentType: String, slideNumber: Int?, sourcePath: String) -> [ProcessedChunk] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return [] }

        // If text is small enough, return as single chunk
        if cleaned.count <= Self.targetChunkSize {
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
            if currentChunk.count + paragraph.count + 2 > Self.targetChunkSize && !currentChunk.isEmpty {
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
                let overlap = String(currentChunk.suffix(Self.overlapSize))
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
