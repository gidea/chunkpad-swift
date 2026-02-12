import Foundation

// MARK: - Chunk File Service

/// Writes and reads chunk markdown files to/from disk.
/// One .md file per source document; chunks are sections with `## Chunk N` headers.
/// Output goes to `{root}/_chunks/` (inside the selected folder) so the app can write
/// within the user-granted security-scoped access from NSOpenPanel.
struct ChunkFileService {

    private var fileManager: FileManager { FileManager.default }

    // MARK: - Path Computation

    /// Returns the `{root}/_chunks/` URL (inside the root folder) for sandbox compatibility.
    func chunksRootURL(for rootFolderURL: URL) -> URL {
        rootFolderURL.standardized.appendingPathComponent("_chunks")
    }

    /// Returns the chunk file URL for a source file given the root folder.
    /// Example: root=MyDocs, source=MyDocs/report.pdf → MyDocs_chunks/report.pdf.md
    func chunkFileURL(for sourceURL: URL, rootFolderURL: URL) -> URL {
        let root = rootFolderURL.standardized
        let source = sourceURL.standardized
        let rootPath = root.path
        let sourcePath = source.path

        guard sourcePath.hasPrefix(rootPath) else {
            return chunksRootURL(for: rootFolderURL).appendingPathComponent(source.lastPathComponent).appendingPathExtension("md")
        }

        let relativePath = String(sourcePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let chunksRoot = chunksRootURL(for: rootFolderURL)
        let chunkFilePath = (relativePath as NSString).appendingPathExtension("md") ?? "\(relativePath).md"
        return chunksRoot.appendingPathComponent(chunkFilePath)
    }

    // MARK: - Write

    /// Writes chunks to a markdown file. Creates parent directories as needed.
    /// Format: `## Chunk 1\ncontent...\n\n## Chunk 2\n...`
    func writeChunks(
        _ chunks: [ProcessedChunk],
        sourceFileURL: URL,
        rootFolderURL: URL
    ) throws -> URL {
        let chunkURL = chunkFileURL(for: sourceFileURL, rootFolderURL: rootFolderURL)
        let parentDir = chunkURL.deletingLastPathComponent()

        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var lines: [String] = []
        for (index, chunk) in chunks.enumerated() {
            lines.append("## Chunk \(index + 1)")
            lines.append(chunk.content)
            if index < chunks.count - 1 {
                lines.append("")
            }
        }
        let content = lines.joined(separator: "\n")
        try content.write(to: chunkURL, atomically: true, encoding: .utf8)
        return chunkURL
    }

    // MARK: - Read / Parse

    /// Parses a chunk markdown file back into ProcessedChunk values.
    /// Uses `## Chunk N` headers to split sections.
    func readChunkFile(at url: URL, sourceFilePath: String, documentType: String) throws -> [ProcessedChunk] {
        let content = try String(contentsOf: url, encoding: .utf8)

        // Regex: ## Chunk (\d+) followed by content until next ## Chunk or end
        let pattern = ##"## Chunk (\d+)\n([\s\S]*?)(?=## Chunk \d+\n|\z)"##
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(content.startIndex..., in: content)

        var chunks: [ProcessedChunk] = []
        let matches = regex.matches(in: content, range: nsRange)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let indexRange = Range(match.range(at: 1), in: content),
                  let contentRange = Range(match.range(at: 2), in: content) else { continue }

            let indexStr = String(content[indexRange])
            let chunkContent = String(content[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkContent.isEmpty, let _ = Int(indexStr) else { continue }

            let title = "Chunk \(indexStr)"
            chunks.append(ProcessedChunk(
                title: title,
                content: chunkContent,
                documentType: documentType,
                slideNumber: nil,
                sourcePath: sourceFilePath
            ))
        }

        return chunks.sorted { c1, c2 in
            let n1 = Int(c1.title.replacingOccurrences(of: "Chunk ", with: "")) ?? 0
            let n2 = Int(c2.title.replacingOccurrences(of: "Chunk ", with: "")) ?? 0
            return n1 < n2
        }
    }

    /// Parses a chunk file using metadata from the file path to infer source path.
    func readChunkFile(at url: URL) throws -> [ProcessedChunk] {
        let ext = IndexedDocument.DocumentType(fromExtension: url.pathExtension)
        let docType = ext == .unknown ? "txt" : ext.rawValue
        let sourcePath = url.path
        return try readChunkFile(at: url, sourceFilePath: sourcePath, documentType: docType)
    }

    // MARK: - Discovery

    /// Recursively discovers all .md chunk files under chunksRootURL.
    func discoverChunkFiles(in chunksRootURL: URL) throws -> [ChunkFileInfo] {
        let root = chunksRootURL.standardized
        var results: [ChunkFileInfo] = []

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "md" else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }

            let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
            let lastModified = attrs[.modificationDate] as? Date ?? Date()

            let sourcePath = inferSourcePath(from: fileURL, chunksRoot: root)
            let docType = (sourcePath as NSString).pathExtension.lowercased()
            let documentType = docType.isEmpty ? "md" : docType
            let chunks = (try? readChunkFile(at: fileURL, sourceFilePath: sourcePath, documentType: documentType)) ?? []

            results.append(ChunkFileInfo(
                fileURL: fileURL,
                sourceFilePath: sourcePath,
                chunks: chunks,
                lastModified: lastModified
            ))
        }

        return results
    }

    /// Infer source document path from chunk file path.
    /// report.pdf.md in MyDocs/_chunks/subdir/ → original source: MyDocs/subdir/report.pdf
    private func inferSourcePath(from chunkFileURL: URL, chunksRoot: URL) -> String {
        let chunkPath = chunkFileURL.standardized.path
        let rootPath = chunksRoot.path
        guard chunkPath.hasPrefix(rootPath) else { return chunkPath }
        let relative = String(chunkPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let relativeWithoutMd = (relative as NSString).deletingPathExtension
        let sourceRootPath = (rootPath as NSString).deletingLastPathComponent
        return (sourceRootPath as NSString).appendingPathComponent(relativeWithoutMd)
    }
}
