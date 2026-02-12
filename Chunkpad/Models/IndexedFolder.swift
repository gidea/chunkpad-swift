import Foundation

// MARK: - Chunk File Info

/// Represents one markdown chunk file on disk.
struct ChunkFileInfo: Identifiable, Sendable {
    let id = UUID()
    let fileURL: URL
    let sourceFilePath: String
    var chunks: [ProcessedChunk]
    let lastModified: Date

    var fileName: String { fileURL.lastPathComponent }
}

// MARK: - Indexed Folder

/// Tracks a user-selected root folder and its parallel chunks directory.
struct IndexedFolder: Codable, Sendable {
    let rootURL: URL
    let chunksRootURL: URL

    /// Database ID when persisted. Nil for in-memory instances.
    var id: String?
    var createdAt: Date?
    var lastProcessedAt: Date?
    var fileCount: Int
    var chunkCount: Int

    /// Security-scoped bookmark data for restoring sandbox access after relaunch.
    var bookmarkData: Data?

    /// Whether the folder is currently accessible (bookmark resolved successfully).
    /// Runtime-only; not persisted to DB or Codable.
    var isAccessible: Bool = true

    init(rootURL: URL, chunksRootURL: URL? = nil, id: String? = nil, createdAt: Date? = nil, lastProcessedAt: Date? = nil, fileCount: Int = 0, chunkCount: Int = 0, bookmarkData: Data? = nil) {
        self.rootURL = rootURL.standardized
        self.chunksRootURL = chunksRootURL ?? Self.defaultChunksRoot(for: rootURL)
        self.id = id
        self.createdAt = createdAt
        self.lastProcessedAt = lastProcessedAt
        self.fileCount = fileCount
        self.chunkCount = chunkCount
        self.bookmarkData = bookmarkData
    }

    private static func defaultChunksRoot(for rootURL: URL) -> URL {
        rootURL.standardized.appendingPathComponent("_chunks")
    }

    // Codable support for URL (legacy; DB uses separate mapping).
    // `isAccessible` is excluded — it's runtime-only state.
    enum CodingKeys: String, CodingKey {
        case rootPath, chunksRootPath, bookmarkData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rootURL = URL(fileURLWithPath: try c.decode(String.self, forKey: .rootPath))
        chunksRootURL = URL(fileURLWithPath: try c.decode(String.self, forKey: .chunksRootPath))
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
        id = nil
        createdAt = nil
        lastProcessedAt = nil
        fileCount = 0
        chunkCount = 0
        isAccessible = true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rootURL.path, forKey: .rootPath)
        try c.encode(chunksRootURL.path, forKey: .chunksRootPath)
        try c.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }
}
