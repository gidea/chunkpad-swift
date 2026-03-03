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

    /// Default chunk size / overlap (characters). Derived from the embedding model's max token window.
    static let defaultChunkSizeChars = EmbeddingService.maxTokenWindow * 4   // ~512 tokens × 4
    static let defaultOverlapChars = 400      // ~100 tokens × 4

    // MARK: - Parse File

    /// Process a single file using the appropriate extraction method.
    /// - Parameters:
    ///   - url: Path to the document.
    ///   - chunkSizeChars: Target chunk size in characters. Defaults to model's max token window × 4.
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
    ///   - skipped: Parse-failed file URLs and their error reasons are appended here.
    func processDirectory(
        at url: URL,
        recursive: Bool = true,
        chunkSizeChars: Int = defaultChunkSizeChars,
        overlapChars: Int = defaultOverlapChars,
        skipped: inout [(url: URL, reason: String)]
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
                skipped.append((url: fileURL, reason: error.localizedDescription))
            }
        }

        return results
    }

    /// Backward-compatible overload (silently ignores skipped files).
    func processDirectory(
        at url: URL,
        recursive: Bool = true,
        chunkSizeChars: Int = defaultChunkSizeChars,
        overlapChars: Int = defaultOverlapChars
    ) async throws -> [URL: [ProcessedChunk]] {
        var ignored: [(url: URL, reason: String)] = []
        return try await processDirectory(
            at: url,
            recursive: recursive,
            chunkSizeChars: chunkSizeChars,
            overlapChars: overlapChars,
            skipped: &ignored
        )
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

            // Detect and convert tabular content, then wrap in markdown
            let processedText = detectAndConvertTables(in: text)
            let markdown = "# \(fileName) — Page \(pageIndex + 1)\n\n\(processedText)"

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
    /// Converts to HTML first to preserve table structure, then parses tables into markdown format.
    /// Non-table content is extracted as plain text with HTML tags stripped.
    private func processViaTextutil(
        at url: URL,
        type: IndexedDocument.DocumentType,
        chunkSizeChars: Int,
        overlapChars: Int
    ) async throws -> [ProcessedChunk] {
        let text = try await convertTextutilToMarkdown(at: url)
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

    /// Convert a rich document to markdown via HTML intermediary.
    /// Tables are preserved as markdown tables; other content is stripped to plain text.
    private func convertTextutilToMarkdown(at url: URL) async throws -> String {
        let html = try await runTextutilHTML(at: url)
        return htmlToMarkdown(html)
    }

    /// Run `textutil -convert html -stdout <path>` and return the HTML output.
    private func runTextutilHTML(at url: URL) async throws -> String {
        try await runTextutilProcess(at: url, format: "html")
    }

    /// Run `textutil -convert <format> -stdout <path>` and return the output.
    private func runTextutilProcess(at url: URL, format: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", format, "-stdout", url.path]

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

    // MARK: - HTML → Markdown Conversion (Table-Aware)

    /// Convert HTML to markdown, preserving table structure as markdown tables.
    /// Non-table content is stripped of HTML tags and normalized.
    private func htmlToMarkdown(_ html: String) -> String {
        var result = ""
        var searchStart = html.startIndex

        // Process the HTML by finding <table>...</table> blocks
        while searchStart < html.endIndex {
            let remaining = html[searchStart...]

            // Find next <table
            guard let tableOpenRange = remaining.range(of: "<table", options: .caseInsensitive) else {
                // No more tables — strip remaining HTML and append
                let text = stripHTMLTags(String(remaining))
                result += text
                break
            }

            // Append stripped text before the table
            let beforeTable = html[searchStart..<tableOpenRange.lowerBound]
            let strippedBefore = stripHTMLTags(String(beforeTable))
            result += strippedBefore

            // Find the closing </table>
            let afterTableOpen = html[tableOpenRange.lowerBound...]
            guard let tableCloseRange = afterTableOpen.range(of: "</table>", options: .caseInsensitive) else {
                // Malformed HTML — no closing tag; strip rest and break
                let text = stripHTMLTags(String(afterTableOpen))
                result += text
                break
            }

            // Extract the full table HTML
            let tableHTML = String(html[tableOpenRange.lowerBound..<tableCloseRange.upperBound])
            let markdownTable = parseHTMLTable(tableHTML)

            if !markdownTable.isEmpty {
                result += "\n\n" + markdownTable + "\n\n"
            }

            searchStart = tableCloseRange.upperBound
        }

        // Normalize excessive whitespace
        return normalizeWhitespace(result)
    }

    /// Parse an HTML table into markdown table format.
    /// Returns a string like:
    /// ```
    /// | Header 1 | Header 2 |
    /// |---|---|
    /// | Cell 1 | Cell 2 |
    /// ```
    private func parseHTMLTable(_ tableHTML: String) -> String {
        // Extract all <tr>...</tr> row blocks
        var rows: [[String]] = []
        var rowSearchStart = tableHTML.startIndex

        while rowSearchStart < tableHTML.endIndex {
            let remaining = tableHTML[rowSearchStart...]
            guard let trOpen = remaining.range(of: "<tr", options: .caseInsensitive) else { break }
            guard let trClose = tableHTML[trOpen.lowerBound...].range(of: "</tr>", options: .caseInsensitive) else { break }

            let rowHTML = String(tableHTML[trOpen.lowerBound..<trClose.upperBound])
            let cells = extractTableCells(from: rowHTML)
            if !cells.isEmpty {
                rows.append(cells)
            }

            rowSearchStart = trClose.upperBound
        }

        guard !rows.isEmpty else { return "" }

        // Normalize column count (pad shorter rows)
        let maxCols = rows.map(\.count).max() ?? 0
        guard maxCols > 0 else { return "" }

        var normalized = rows.map { row in
            row + Array(repeating: "", count: max(0, maxCols - row.count))
        }

        // Build markdown table
        var lines: [String] = []

        // First row as header
        let headerRow = normalized.removeFirst()
        lines.append("| " + headerRow.joined(separator: " | ") + " |")
        lines.append("|" + Array(repeating: "---", count: maxCols).joined(separator: "|") + "|")

        // Remaining rows
        for row in normalized {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }

        return lines.joined(separator: "\n")
    }

    /// Extract cell contents from a <tr>...</tr> row. Handles both <th> and <td>.
    private func extractTableCells(from rowHTML: String) -> [String] {
        var cells: [String] = []
        var searchStart = rowHTML.startIndex

        while searchStart < rowHTML.endIndex {
            let remaining = rowHTML[searchStart...]

            // Find next <td or <th
            var nextCell: Range<String.Index>?
            var cellTag = ""

            if let tdRange = remaining.range(of: "<td", options: .caseInsensitive),
               let thRange = remaining.range(of: "<th", options: .caseInsensitive) {
                if tdRange.lowerBound < thRange.lowerBound {
                    nextCell = tdRange; cellTag = "td"
                } else {
                    nextCell = thRange; cellTag = "th"
                }
            } else if let tdRange = remaining.range(of: "<td", options: .caseInsensitive) {
                nextCell = tdRange; cellTag = "td"
            } else if let thRange = remaining.range(of: "<th", options: .caseInsensitive) {
                nextCell = thRange; cellTag = "th"
            }

            guard let cellOpen = nextCell else { break }

            // Find the > that closes the opening tag (handles attributes like <td class="...">)
            guard let tagClose = rowHTML[cellOpen.lowerBound...].range(of: ">") else { break }

            // Find the closing </td> or </th>
            let closeTag = "</\(cellTag)>"
            guard let cellClose = rowHTML[tagClose.upperBound...].range(of: closeTag, options: .caseInsensitive) else { break }

            let cellContent = String(rowHTML[tagClose.upperBound..<cellClose.lowerBound])
            let stripped = stripHTMLTags(cellContent)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "|", with: "\\|")  // Escape pipes in cell content
            cells.append(stripped)

            searchStart = cellClose.upperBound
        }

        return cells
    }

    /// Strip HTML tags from a string and decode common HTML entities.
    private func stripHTMLTags(_ html: String) -> String {
        // Replace <br>, <br/>, <br /> with newlines
        var text = html.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        // Replace </p>, </div>, </li> with newlines for paragraph breaks
        text = text.replacingOccurrences(of: "</(?:p|div|li|h[1-6])>", with: "\n", options: .regularExpression)

        // Strip all remaining HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#160;", with: " ")

        return text
    }

    /// Normalize excessive whitespace: collapse multiple blank lines, trim lines.
    private func normalizeWhitespace(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Collapse runs of empty lines into at most two newlines
        var result: [String] = []
        var blankCount = 0
        for line in lines {
            if line.isEmpty {
                blankCount += 1
                if blankCount <= 2 {
                    result.append(line)
                }
            } else {
                blankCount = 0
                result.append(line)
            }
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Heuristic Table Detection (PDF / Plain Text)

    /// Detect tabular content in plain text extracted from PDFs or text files.
    /// Looks for lines with tab separators or consistent multi-space column alignment.
    /// Converts detected table blocks to markdown table format.
    private func detectAndConvertTables(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var i = 0

        while i < lines.count {
            // Check if this line starts a tab-separated table block
            if looksLikeTabSeparatedRow(lines[i]) {
                // Collect consecutive tab-separated lines
                var tableLines: [String] = []
                while i < lines.count && looksLikeTabSeparatedRow(lines[i]) {
                    tableLines.append(lines[i])
                    i += 1
                }

                // Need at least 2 rows to be a table
                if tableLines.count >= 2 {
                    let markdownTable = convertTextTableToMarkdown(tableLines, separator: "\t")
                    result.append(markdownTable)
                } else {
                    result.append(contentsOf: tableLines)
                }
                continue
            }

            // Check for multi-space aligned columns (3+ consecutive lines with consistent spacing)
            if i + 2 < lines.count {
                let columns = detectAlignedColumns(lines: Array(lines[i...min(i + 4, lines.count - 1)]))
                if let cols = columns, cols.count >= 2 {
                    // Collect all consecutive lines that match this column alignment
                    var tableLines: [String] = []
                    var j = i
                    while j < lines.count {
                        let lineCols = splitByColumnPositions(lines[j], positions: cols)
                        if lineCols.count >= 2 && !lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                            tableLines.append(lines[j])
                            j += 1
                        } else {
                            break
                        }
                    }

                    if tableLines.count >= 3 {
                        let markdownTable = convertAlignedTableToMarkdown(tableLines, columnPositions: cols)
                        result.append(markdownTable)
                        i = j
                        continue
                    }
                }
            }

            result.append(lines[i])
            i += 1
        }

        return result.joined(separator: "\n")
    }

    /// Check if a line appears to be tab-separated with 2+ columns.
    private func looksLikeTabSeparatedRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let tabCount = trimmed.filter { $0 == "\t" }.count
        return tabCount >= 1
    }

    /// Convert tab/delimiter-separated lines into a markdown table.
    private func convertTextTableToMarkdown(_ lines: [String], separator: String) -> String {
        let rows = lines.map { line in
            line.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "|", with: "\\|") }
        }

        guard !rows.isEmpty else { return "" }
        let maxCols = rows.map(\.count).max() ?? 0
        guard maxCols > 0 else { return "" }

        let normalized = rows.map { row in
            row + Array(repeating: "", count: max(0, maxCols - row.count))
        }

        var mdLines: [String] = []
        mdLines.append("| " + normalized[0].joined(separator: " | ") + " |")
        mdLines.append("|" + Array(repeating: "---", count: maxCols).joined(separator: "|") + "|")
        for row in normalized.dropFirst() {
            mdLines.append("| " + row.joined(separator: " | ") + " |")
        }
        return mdLines.joined(separator: "\n")
    }

    /// Detect consistent multi-space column boundaries across a sample of lines.
    /// Returns column start positions if a consistent pattern is found.
    private func detectAlignedColumns(lines: [String]) -> [Int]? {
        guard lines.count >= 3 else { return nil }

        // Find positions where 3+ spaces appear in most lines
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard nonEmpty.count >= 3 else { return nil }

        // Collect gap positions (start of 3+ space runs) for each line
        var gapPositionSets: [[Int]] = []
        for line in nonEmpty {
            var gaps: [Int] = []
            var spaceCount = 0
            for (idx, char) in line.enumerated() {
                if char == " " {
                    spaceCount += 1
                } else {
                    if spaceCount >= 3 {
                        gaps.append(idx - spaceCount)
                    }
                    spaceCount = 0
                }
            }
            guard !gaps.isEmpty else { return nil }
            gapPositionSets.append(gaps)
        }

        // Find gap positions that appear in at least 60% of lines (within ±2 tolerance)
        guard let firstGaps = gapPositionSets.first else { return nil }
        var consistentPositions: [Int] = []

        for gapPos in firstGaps {
            var matchCount = 0
            for gapSet in gapPositionSets {
                if gapSet.contains(where: { abs($0 - gapPos) <= 2 }) {
                    matchCount += 1
                }
            }
            if matchCount >= (nonEmpty.count * 6) / 10 {  // 60% threshold
                consistentPositions.append(gapPos)
            }
        }

        guard consistentPositions.count >= 1 else { return nil }
        return [0] + consistentPositions.sorted()
    }

    /// Split a line into columns based on detected column start positions.
    private func splitByColumnPositions(_ line: String, positions: [Int]) -> [String] {
        var columns: [String] = []
        let chars = Array(line)

        for (idx, startPos) in positions.enumerated() {
            let endPos = idx + 1 < positions.count ? positions[idx + 1] : chars.count
            guard startPos < chars.count else {
                columns.append("")
                continue
            }
            let actualEnd = min(endPos, chars.count)
            let col = String(chars[startPos..<actualEnd]).trimmingCharacters(in: .whitespaces)
            columns.append(col)
        }

        return columns
    }

    /// Convert aligned-column text lines into a markdown table.
    private func convertAlignedTableToMarkdown(_ lines: [String], columnPositions: [Int]) -> String {
        let rows = lines.map { line in
            splitByColumnPositions(line, positions: columnPositions)
                .map { $0.replacingOccurrences(of: "|", with: "\\|") }
        }

        guard !rows.isEmpty else { return "" }
        let maxCols = rows.map(\.count).max() ?? 0
        guard maxCols > 0 else { return "" }

        let normalized = rows.map { row in
            row + Array(repeating: "", count: max(0, maxCols - row.count))
        }

        var mdLines: [String] = []
        mdLines.append("| " + normalized[0].joined(separator: " | ") + " |")
        mdLines.append("|" + Array(repeating: "---", count: maxCols).joined(separator: "|") + "|")
        for row in normalized.dropFirst() {
            mdLines.append("| " + row.joined(separator: " | ") + " |")
        }
        return mdLines.joined(separator: "\n")
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

        // Detect and convert tabular content, then wrap in markdown
        let processedText = detectAndConvertTables(in: text)
        let markdown = "# \(fileName)\n\n\(processedText)"

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

    // MARK: - Section-Aware Chunking

    /// A parsed markdown section: heading + body content.
    private struct MarkdownSection {
        let heading: String       // e.g., "## Architecture Overview"
        let headingText: String   // e.g., "Architecture Overview" (without # prefix)
        let level: Int            // 1-6
        let content: String       // Full content including heading line
        let headingPath: [String] // Hierarchical path, e.g., ["Document", "Architecture", "Overview"]
    }

    /// Split text into overlapping chunks of approximately `chunkSizeChars` characters.
    /// Uses section-aware splitting when markdown headings are present (splits at heading boundaries).
    /// Falls back to paragraph-boundary splitting for texts without headings or for oversized sections.
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

        // Check if text has markdown headings (outside of fenced code blocks)
        let hasHeadings = containsMarkdownHeadings(cleaned)

        if hasHeadings {
            return splitIntoSectionChunks(
                text: cleaned,
                title: title,
                documentType: documentType,
                slideNumber: slideNumber,
                sourcePath: sourcePath,
                chunkSizeChars: chunkSizeChars,
                overlapChars: overlapChars
            )
        }

        // Fallback: paragraph-based splitting for texts without headings
        return splitIntoParagraphChunks(
            text: cleaned,
            title: title,
            documentType: documentType,
            slideNumber: slideNumber,
            sourcePath: sourcePath,
            chunkSizeChars: chunkSizeChars,
            overlapChars: overlapChars
        )
    }

    /// Check if text contains markdown headings outside of fenced code blocks.
    private func containsMarkdownHeadings(_ text: String) -> Bool {
        // Strip fenced code blocks first to avoid false positives
        let withoutCode = removeFencedCodeBlocks(text)
        // Look for heading pattern: line starting with 1-6 # followed by space
        return withoutCode.range(of: #"(?m)^#{1,6}\s+"#, options: .regularExpression) != nil
    }

    /// Remove fenced code blocks (``` ... ```) from text to avoid matching headings inside code.
    private func removeFencedCodeBlocks(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(?m)^```[^\n]*\n[\s\S]*?^```"#,
            with: "",
            options: .regularExpression
        )
    }

    /// Parse markdown text into sections by heading boundaries.
    private func parseMarkdownSections(_ text: String) -> [MarkdownSection] {
        let lines = text.components(separatedBy: .newlines)
        var sections: [MarkdownSection] = []
        var currentHeading = ""
        var currentHeadingText = ""
        var currentLevel = 0
        var currentLines: [String] = []
        var headingStack: [(text: String, level: Int)] = []
        var inCodeBlock = false

        for line in lines {
            // Track fenced code blocks
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                currentLines.append(line)
                continue
            }

            if inCodeBlock {
                currentLines.append(line)
                continue
            }

            // Check if this line is a heading
            if let (level, headingText) = parseHeadingLine(line) {
                // Emit previous section if it has content
                if !currentLines.isEmpty {
                    let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        let path = headingStack.map(\.text) + (currentHeadingText.isEmpty ? [] : [currentHeadingText])
                        sections.append(MarkdownSection(
                            heading: currentHeading,
                            headingText: currentHeadingText,
                            level: currentLevel,
                            content: content,
                            headingPath: path.isEmpty ? [] : path
                        ))
                    }
                }

                // Update heading stack — pop headings at same or deeper level
                while let last = headingStack.last, last.level >= level {
                    headingStack.removeLast()
                }
                headingStack.append((text: headingText, level: level))

                // Start new section
                currentHeading = line
                currentHeadingText = headingText
                currentLevel = level
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }

        // Emit final section
        if !currentLines.isEmpty {
            let content = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                let path = headingStack.map(\.text)
                sections.append(MarkdownSection(
                    heading: currentHeading,
                    headingText: currentHeadingText,
                    level: currentLevel,
                    content: content,
                    headingPath: path
                ))
            }
        }

        return sections
    }

    /// Parse a line as a markdown heading. Returns (level, text) or nil.
    private func parseHeadingLine(_ line: String) -> (Int, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }

        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 }
            else { break }
        }

        guard level >= 1 && level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        return (level, text)
    }

    /// Split text into chunks at markdown heading boundaries.
    /// Sections that fit within chunkSizeChars become one chunk each.
    /// Oversized sections fall back to paragraph splitting.
    private func splitIntoSectionChunks(
        text: String,
        title: String,
        documentType: String,
        slideNumber: Int?,
        sourcePath: String,
        chunkSizeChars: Int,
        overlapChars: Int
    ) -> [ProcessedChunk] {
        let sections = parseMarkdownSections(text)
        guard !sections.isEmpty else {
            // No sections parsed — fall back to paragraph splitting
            return splitIntoParagraphChunks(
                text: text, title: title, documentType: documentType,
                slideNumber: slideNumber, sourcePath: sourcePath,
                chunkSizeChars: chunkSizeChars, overlapChars: overlapChars
            )
        }

        var chunks: [ProcessedChunk] = []

        for section in sections {
            let sectionTitle = buildHierarchicalTitle(from: section.headingPath)

            if section.content.count <= chunkSizeChars {
                // Section fits in one chunk
                chunks.append(ProcessedChunk(
                    title: sectionTitle,
                    content: section.content,
                    documentType: documentType,
                    slideNumber: slideNumber,
                    sourcePath: sourcePath
                ))
            } else {
                // Section is too large — split by paragraphs within it
                let subChunks = splitIntoParagraphChunks(
                    text: section.content,
                    title: sectionTitle,
                    documentType: documentType,
                    slideNumber: slideNumber,
                    sourcePath: sourcePath,
                    chunkSizeChars: chunkSizeChars,
                    overlapChars: overlapChars
                )
                chunks.append(contentsOf: subChunks)
            }
        }

        return chunks
    }

    /// Build a hierarchical title from heading path, e.g., "Document > Section > Subsection".
    private func buildHierarchicalTitle(from headingPath: [String]) -> String {
        guard !headingPath.isEmpty else { return "Untitled" }
        return headingPath.joined(separator: " > ")
    }

    // MARK: - Paragraph-Based Chunking (Fallback)

    /// Split text into overlapping chunks at paragraph boundaries (\n\n).
    /// Used as fallback when no markdown headings are present or for oversized sections.
    private func splitIntoParagraphChunks(
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

        // Single-pass paragraph splitting: scan for "\n\n" boundaries without
        // allocating an intermediate [String] array. Paragraphs are trimmed inline.
        var chunks: [ProcessedChunk] = []
        var currentChunk = ""
        var chunkIndex = 0
        var hasParagraphs = false

        var searchStart = cleaned.startIndex
        while searchStart < cleaned.endIndex {
            // Find next "\n\n" boundary
            let paragraphEnd: String.Index
            if let range = cleaned.range(of: "\n\n", range: searchStart..<cleaned.endIndex) {
                paragraphEnd = range.lowerBound
                hasParagraphs = true
            } else {
                paragraphEnd = cleaned.endIndex
            }

            // Extract and trim paragraph
            let rawParagraph = cleaned[searchStart..<paragraphEnd]
            let paragraph = rawParagraph.trimmingCharacters(in: .whitespacesAndNewlines)

            // Advance past the "\n\n" delimiter (or to end)
            if paragraphEnd < cleaned.endIndex {
                searchStart = cleaned.index(paragraphEnd, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            } else {
                searchStart = cleaned.endIndex
            }

            guard !paragraph.isEmpty else { continue }

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
                title: hasParagraphs ? "\(title) [\(chunkIndex + 1)]" : title,
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
