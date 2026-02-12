import Foundation
import SQLite3
import CSQLiteVec

// MARK: - Database Errors

enum DatabaseError: LocalizedError, Sendable {
    case connectionFailed(String)
    case queryFailed(String)
    case schemaCreationFailed(String)
    case vecInitFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Database connection failed: \(msg)"
        case .queryFailed(let msg): return "Query failed: \(msg)"
        case .schemaCreationFailed(let msg): return "Schema creation failed: \(msg)"
        case .vecInitFailed(let msg): return "sqlite-vec init failed: \(msg)"
        }
    }
}

// MARK: - Database Service

/// Thin async wrapper around SQLite + sqlite-vec + FTS5.
/// All database operations run on a dedicated serial actor to prevent concurrency issues.
actor DatabaseService {

    /// Current schema version. Bump when adding migrations.
    static let currentSchemaVersion = 9

    // nonisolated(unsafe) because deinit needs access and OpaquePointer is not Sendable.
    // Thread safety is guaranteed by the actor isolation — deinit only runs after
    // all references are released, at which point no other code can access this.
    private nonisolated(unsafe) var db: OpaquePointer?

    /// The path to the SQLite database file.
    let databasePath: String

    /// Cached date formatter to avoid repeated allocation in hot paths.
    private let dateFormatter = ISO8601DateFormatter()

    // MARK: - Initialization

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Chunkpad", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        self.databasePath = appSupport.appendingPathComponent("chunkpad.db").path
    }

    /// For testing with custom path
    init(path: String) {
        self.databasePath = path
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Connection

    func connect() throws {
        guard db == nil else { return }

        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databasePath, &dbPointer, flags, nil)

        guard rc == SQLITE_OK, let dbPointer else {
            let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw DatabaseError.connectionFailed(msg)
        }

        self.db = dbPointer

        // Enable WAL mode for better concurrent read performance
        try execute("PRAGMA journal_mode=WAL")

        // Register sqlite-vec extension
        try registerSQLiteVec()

        // Create base schema and run migrations
        try createSchema()
        try migrate()
    }

    func disconnect() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    var isConnected: Bool {
        db != nil
    }

    // MARK: - sqlite-vec Registration

    private func registerSQLiteVec() throws {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_vec_init(db, &errMsg, nil)

        guard rc == SQLITE_OK else {
            let msg = errMsg.flatMap { String(cString: $0) } ?? "sqlite-vec init returned \(rc)"
            errMsg.flatMap { sqlite3_free($0) }
            throw DatabaseError.vecInitFailed(msg)
        }
    }

    // MARK: - Schema

    private func createSchema() throws {
        try execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)")

        // Regular table for document metadata
        try execute("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                file_name TEXT NOT NULL,
                file_path TEXT NOT NULL UNIQUE,
                document_type TEXT NOT NULL,
                chunk_count INTEGER DEFAULT 0,
                indexed_at TEXT NOT NULL,
                file_size INTEGER DEFAULT 0
            )
        """)

        // Regular table for chunks (text content + metadata)
        try execute("""
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                title TEXT NOT NULL,
                summary TEXT,
                content TEXT NOT NULL,
                document_type TEXT,
                slide_number INTEGER,
                source_path TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
            )
        """)

        // vec0 virtual table for vector embeddings (cosine distance)
        // Uses auxiliary columns for data returned with KNN results
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS vec_chunks USING vec0(
                chunk_id TEXT PRIMARY KEY,
                embedding float[768] distance_metric=cosine,
                document_type TEXT,
                +title TEXT,
                +source_path TEXT
            )
        """)

        // FTS5 virtual table for full-text keyword search
        try execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                title,
                content,
                content='chunks',
                content_rowid='rowid'
            )
        """)

        // Triggers to keep FTS5 in sync with chunks table
        try execute("""
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
            END
        """)

        try execute("""
            CREATE TRIGGER IF NOT EXISTS chunks_au AFTER UPDATE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
                INSERT INTO chunks_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END
        """)
    }

    // MARK: - Migrations

    private func querySchemaVersion() throws -> Int {
        let rows: [Int] = try query("SELECT COALESCE(MAX(version), 0) FROM schema_version") { stmt in
            Int(sqlite3_column_int64(stmt, 0))
        }
        return rows.first ?? 0
    }

    private func migrate() throws {
        let current = try querySchemaVersion()
        guard current < Self.currentSchemaVersion else { return }
        for v in (current + 1)...Self.currentSchemaVersion {
            try runMigration(version: v)
        }
    }

    private func runMigration(version: Int) throws {
        try execute("BEGIN TRANSACTION")
        do {
            switch version {
            case 1:
                try execute("DROP TABLE IF EXISTS messages")
            case 2:
                try execute("CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON chunks(document_id)")
            case 3:
                try execute("""
                    CREATE TABLE IF NOT EXISTS indexed_folders (
                        id TEXT PRIMARY KEY,
                        root_path TEXT NOT NULL UNIQUE,
                        chunks_root_path TEXT NOT NULL,
                        created_at TEXT NOT NULL,
                        last_processed_at TEXT,
                        file_count INTEGER DEFAULT 0,
                        chunk_count INTEGER DEFAULT 0
                    )
                """)
            case 4:
                try migrateIndexedFoldersFromUserDefaults()
            case 5:
                try execute("""
                    CREATE TABLE IF NOT EXISTS embedded_chunk_refs (
                        chunk_ref_id TEXT PRIMARY KEY,
                        chunk_id TEXT,
                        content_hash TEXT,
                        embedded_at TEXT NOT NULL
                    )
                """)
            case 6:
                try migrateEmbeddedChunkIdsFromUserDefaults()
            case 7:
                // Remove unused content_hash column from embedded_chunk_refs.
                // SQLite doesn't support DROP COLUMN before 3.35; recreate instead.
                try execute("CREATE TABLE IF NOT EXISTS embedded_chunk_refs_new (chunk_ref_id TEXT PRIMARY KEY, chunk_id TEXT, embedded_at TEXT NOT NULL)")
                try execute("INSERT INTO embedded_chunk_refs_new (chunk_ref_id, chunk_id, embedded_at) SELECT chunk_ref_id, chunk_id, embedded_at FROM embedded_chunk_refs")
                try execute("DROP TABLE embedded_chunk_refs")
                try execute("ALTER TABLE embedded_chunk_refs_new RENAME TO embedded_chunk_refs")
            case 8:
                // Add security-scoped bookmark data column to indexed_folders
                try execute("ALTER TABLE indexed_folders ADD COLUMN bookmark_data BLOB")
            case 9:
                // Add indexes for LIKE prefix queries used by cascade delete and chunk ref lookup
                try execute("CREATE INDEX IF NOT EXISTS idx_chunks_source_path ON chunks(source_path)")
                try execute("CREATE INDEX IF NOT EXISTS idx_embedded_chunk_refs_chunk_ref_id ON embedded_chunk_refs(chunk_ref_id)")
                try execute("CREATE INDEX IF NOT EXISTS idx_documents_file_path ON documents(file_path)")
            default:
                break
            }
            try execute("INSERT OR REPLACE INTO schema_version (version) VALUES (?)", bindings: [.int(Int64(version))])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func migrateIndexedFoldersFromUserDefaults() throws {
        let defaults = UserDefaults.standard
        guard let rootPath = defaults.string(forKey: "indexing_folder_root"),
              let chunksPath = defaults.string(forKey: "indexing_folder_chunks_root") else { return }
        let id = UUID().uuidString
        let now = dateFormatter.string(from: Date())
        try execute("""
            INSERT OR IGNORE INTO indexed_folders (id, root_path, chunks_root_path, created_at, last_processed_at, file_count, chunk_count)
            VALUES (?, ?, ?, ?, ?, 0, 0)
        """, bindings: [.text(id), .text(rootPath), .text(chunksPath), .text(now), .null])
        defaults.removeObject(forKey: "indexing_folder_root")
        defaults.removeObject(forKey: "indexing_folder_chunks_root")
    }

    private func migrateEmbeddedChunkIdsFromUserDefaults() throws {
        let defaults = UserDefaults.standard
        guard let ids = defaults.stringArray(forKey: "indexing_embedded_chunk_ids"), !ids.isEmpty else { return }
        let now = dateFormatter.string(from: Date())
        for id in ids {
            try execute("""
                INSERT OR IGNORE INTO embedded_chunk_refs (chunk_ref_id, chunk_id, content_hash, embedded_at)
                VALUES (?, ?, ?, ?)
            """, bindings: [.text(id), .null, .null, .text(now)])
        }
        defaults.removeObject(forKey: "indexing_embedded_chunk_ids")
    }

    // MARK: - Document CRUD

    func insertDocument(_ doc: IndexedDocument) throws {
        let sql = """
            INSERT OR REPLACE INTO documents (id, file_name, file_path, document_type, chunk_count, indexed_at, file_size)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        try execute(sql, bindings: [
            .text(doc.id),
            .text(doc.fileName),
            .text(doc.filePath),
            .text(doc.documentType.rawValue),
            .int(Int64(doc.chunkCount)),
            .text(dateFormatter.string(from: doc.indexedAt)),
            .int(doc.fileSize),
        ])
    }

    /// Inserts a document and all its chunks in a single transaction. Use when embedding is done upfront.
    func insertDocumentWithChunks(document: IndexedDocument, chunksWithEmbeddings: [(Chunk, [Float])]) throws {
        try performTransaction {
            try insertDocument(document)
            for (chunk, embedding) in chunksWithEmbeddings {
                try insertChunkInternal(chunk, documentID: document.id, embedding: embedding)
            }
        }
    }

    /// Internal chunk insert without transaction (for use inside performTransaction or insertDocumentWithChunks).
    private func insertChunkInternal(_ chunk: Chunk, documentID: String, embedding: [Float]) throws {
        try execute("""
            INSERT OR REPLACE INTO chunks (id, document_id, title, summary, content, document_type, slide_number, source_path, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(chunk.id),
            .text(documentID),
            .text(chunk.title),
            chunk.summary.map { .text($0) } ?? .null,
            .text(chunk.content),
            chunk.documentType.map { .text($0) } ?? .null,
            chunk.slideNumber.map { .int(Int64($0)) } ?? .null,
            .text(chunk.sourcePath),
            .text(dateFormatter.string(from: chunk.createdAt)),
        ])
        try insertVectorEmbedding(chunkID: chunk.id, embedding: embedding,
                                   documentType: chunk.documentType,
                                   title: chunk.title, sourcePath: chunk.sourcePath)
    }

    func deleteDocument(id: String) throws {
        try performTransaction {
            try execute("DELETE FROM vec_chunks WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)",
                         bindings: [.text(id)])
            try execute("DELETE FROM chunks WHERE document_id = ?", bindings: [.text(id)])
            try execute("DELETE FROM documents WHERE id = ?", bindings: [.text(id)])
        }
    }

    // MARK: - Indexed Folders

    func insertIndexedFolder(_ folder: IndexedFolder, fileCount: Int, chunkCount: Int) throws {
        let id = folder.id ?? UUID().uuidString
        let now = dateFormatter.string(from: Date())
        try execute("""
            INSERT OR REPLACE INTO indexed_folders (id, root_path, chunks_root_path, created_at, last_processed_at, file_count, chunk_count, bookmark_data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, bindings: [
            .text(id),
            .text(folder.rootURL.path),
            .text(folder.chunksRootURL.path),
            .text(folder.createdAt.map { dateFormatter.string(from: $0) } ?? now),
            .text(now),
            .int(Int64(fileCount)),
            .int(Int64(chunkCount)),
            folder.bookmarkData.map { .blob($0) } ?? .null,
        ])
    }

    /// Updates just the bookmark data for an existing folder (e.g. when refreshing a stale bookmark).
    func updateFolderBookmark(id: String, bookmarkData: Data) throws {
        try execute("UPDATE indexed_folders SET bookmark_data = ? WHERE id = ?", bindings: [
            .blob(bookmarkData),
            .text(id),
        ])
    }

    func fetchIndexedFolders() throws -> [IndexedFolder] {
        return try query("SELECT id, root_path, chunks_root_path, created_at, last_processed_at, file_count, chunk_count, bookmark_data FROM indexed_folders ORDER BY created_at DESC") { stmt in
            // Read bookmark_data BLOB (column 7)
            var bookmarkData: Data?
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL,
               let blobPtr = sqlite3_column_blob(stmt, 7) {
                let blobSize = Int(sqlite3_column_bytes(stmt, 7))
                bookmarkData = Data(bytes: blobPtr, count: blobSize)
            }
            return IndexedFolder(
                rootURL: URL(fileURLWithPath: columnText(stmt, 1)),
                chunksRootURL: URL(fileURLWithPath: columnText(stmt, 2)),
                id: columnText(stmt, 0),
                createdAt: columnTextOptional(stmt, 3).flatMap { self.dateFormatter.date(from: $0) },
                lastProcessedAt: columnTextOptional(stmt, 4).flatMap { self.dateFormatter.date(from: $0) },
                fileCount: Int(sqlite3_column_int64(stmt, 5)),
                chunkCount: Int(sqlite3_column_int64(stmt, 6)),
                bookmarkData: bookmarkData
            )
        }
    }

    func deleteIndexedFolder(id: String) throws {
        try execute("DELETE FROM indexed_folders WHERE id = ?", bindings: [.text(id)])
    }

    /// Cascade-deletes a folder and all its associated data:
    /// documents (by path prefix), their chunks, vec_chunks, embedded_chunk_refs, and the folder record.
    func deleteIndexedFolderCascade(id: String, rootPath: String) throws {
        try performTransaction {
            // Find all document IDs whose file_path starts with the folder's root path
            let docIDs: [String] = try query(
                "SELECT id FROM documents WHERE file_path LIKE ?",
                bindings: [.text(rootPath + "%")]
            ) { stmt in columnText(stmt, 0) }

            for docID in docIDs {
                try execute("DELETE FROM vec_chunks WHERE chunk_id IN (SELECT id FROM chunks WHERE document_id = ?)",
                             bindings: [.text(docID)])
                try execute("DELETE FROM chunks WHERE document_id = ?", bindings: [.text(docID)])
            }
            try execute("DELETE FROM documents WHERE file_path LIKE ?", bindings: [.text(rootPath + "%")])

            // Delete embedded chunk refs that match the folder's chunks root path
            try execute("DELETE FROM embedded_chunk_refs WHERE chunk_ref_id LIKE ?", bindings: [.text(rootPath + "%")])

            // Delete the folder record itself
            try execute("DELETE FROM indexed_folders WHERE id = ?", bindings: [.text(id)])
        }
    }

    /// Deletes all data from all tables. Used for "Clear All Data" action.
    func deleteAllData() throws {
        try performTransaction {
            try execute("DELETE FROM vec_chunks")
            try execute("DELETE FROM chunks")
            try execute("DELETE FROM documents")
            try execute("DELETE FROM embedded_chunk_refs")
            try execute("DELETE FROM indexed_folders")
        }
    }

    // MARK: - Embedded Chunk Refs

    func insertEmbeddedChunkRef(chunkRefId: String, chunkId: String?, embeddedAt: Date) throws {
        try execute("""
            INSERT OR REPLACE INTO embedded_chunk_refs (chunk_ref_id, chunk_id, embedded_at)
            VALUES (?, ?, ?)
        """, bindings: [
            .text(chunkRefId),
            chunkId.map { .text($0) } ?? .null,
            .text(dateFormatter.string(from: embeddedAt)),
        ])
    }

    func fetchEmbeddedChunkRefIds() throws -> Set<String> {
        let rows: [String] = try query("SELECT chunk_ref_id FROM embedded_chunk_refs") { stmt in
            columnText(stmt, 0)
        }
        return Set(rows)
    }

    func deleteEmbeddedChunkRefs(matchingPrefix prefix: String) throws {
        try execute("DELETE FROM embedded_chunk_refs WHERE chunk_ref_id LIKE ?", bindings: [.text(prefix + "%")])
    }

    // MARK: - Document CRUD

    /// Deletes a document by file path if it exists. Used before re-embedding.
    func deleteDocumentByFilePath(_ filePath: String) throws {
        let ids: [String] = try query("SELECT id FROM documents WHERE file_path = ?", bindings: [.text(filePath)]) { stmt in
            columnText(stmt, 0)
        }
        for id in ids {
            try deleteDocument(id: id)
        }
    }

    func allDocuments() throws -> [IndexedDocument] {
        let sql = "SELECT id, file_name, file_path, document_type, chunk_count, indexed_at, file_size FROM documents ORDER BY indexed_at DESC"
        return try query(sql) { stmt in
            IndexedDocument(
                id: columnText(stmt, 0),
                fileName: columnText(stmt, 1),
                filePath: columnText(stmt, 2),
                documentType: .init(fromExtension: columnText(stmt, 3)),
                chunkCount: Int(sqlite3_column_int64(stmt, 4)),
                indexedAt: self.dateFormatter.date(from: columnText(stmt, 5)) ?? .now,
                fileSize: sqlite3_column_int64(stmt, 6)
            )
        }
    }

    func documentCount() throws -> Int {
        let rows: [Int] = try query("SELECT COUNT(*) FROM documents") { stmt in
            Int(sqlite3_column_int64(stmt, 0))
        }
        return rows.first ?? 0
    }

    // MARK: - Chunk CRUD

    func insertChunk(_ chunk: Chunk, documentID: String, embedding: [Float]) throws {
        try performTransaction {
            try insertChunkInternal(chunk, documentID: documentID, embedding: embedding)
        }
    }

    // MARK: - Vector Operations

    private func insertVectorEmbedding(chunkID: String, embedding: [Float],
                                        documentType: String?, title: String, sourcePath: String) throws {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        let sql = """
            INSERT INTO vec_chunks (chunk_id, embedding, document_type, title, source_path)
            VALUES (?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        // Bind chunk_id
        sqlite3_bind_text(stmt, 1, chunkID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        // Bind embedding as float32 blob
        let blobSize = embedding.count * MemoryLayout<Float>.size
        embedding.withUnsafeBufferPointer { buffer in
            sqlite3_bind_blob(stmt, 2, buffer.baseAddress, Int32(blobSize),
                             unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        // Bind metadata
        if let dt = documentType {
            sqlite3_bind_text(stmt, 3, dt, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_text(stmt, 4, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, sourcePath, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Perform KNN vector search using sqlite-vec.
    /// Returns chunk IDs and distances sorted by similarity.
    func vectorSearch(queryEmbedding: [Float], k: Int = 10, documentType: String? = nil) throws -> [(chunkID: String, distance: Double, title: String, sourcePath: String)] {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        var sql: String
        var bindings: [SQLiteBinding]

        if let documentType {
            sql = """
                SELECT chunk_id, distance, title, source_path
                FROM vec_chunks
                WHERE embedding MATCH ?
                  AND k = ?
                  AND document_type = ?
                ORDER BY distance
            """
            bindings = [.blob(embeddingToBlob(queryEmbedding)), .int(Int64(k)), .text(documentType)]
        } else {
            sql = """
                SELECT chunk_id, distance, title, source_path
                FROM vec_chunks
                WHERE embedding MATCH ?
                  AND k = ?
                ORDER BY distance
            """
            bindings = [.blob(embeddingToBlob(queryEmbedding)), .int(Int64(k))]
        }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        for (i, binding) in bindings.enumerated() {
            bind(stmt: stmt!, index: Int32(i + 1), value: binding)
        }

        var results: [(String, Double, String, String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkID = columnText(stmt!, 0)
            let distance = sqlite3_column_double(stmt, 1)
            let title = columnText(stmt!, 2)
            let sourcePath = columnText(stmt!, 3)
            results.append((chunkID, distance, title, sourcePath))
        }

        return results
    }

    /// Full-text search using FTS5.
    func fullTextSearch(query: String, limit: Int = 20) throws -> [(chunkID: String, rank: Double)] {
        let sql = """
            SELECT c.id, chunks_fts.rank
            FROM chunks_fts
            JOIN chunks c ON c.rowid = chunks_fts.rowid
            WHERE chunks_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        return try self.query(sql, bindings: [.text(query), .int(Int64(limit))]) { stmt in
            (columnText(stmt, 0), sqlite3_column_double(stmt, 1))
        }
    }

    /// Hybrid search: combine vector KNN + FTS5 results.
    /// Vector similarity weighted at 70%, keyword relevance at 30%.
    /// Hybrid search combining vector KNN (70 %) and FTS5 keyword match (30 %).
    ///
    /// Returns `ScoredChunk` values so the UI can display relevance and let
    /// users toggle individual chunks on/off before sending context to the LLM.
    ///
    /// - Parameters:
    ///   - queryEmbedding: The 768-dim BGE query embedding.
    ///   - queryText: The raw user query for FTS5.
    ///   - k: Maximum number of results to return.
    ///   - minScore: Minimum combined score (0–1). Chunks below this are discarded
    ///               so irrelevant results never reach the LLM. Default 0.1.
    func hybridSearch(queryEmbedding: [Float], queryText: String, k: Int = 10, minScore: Double = 0.1) throws -> [ScoredChunk] {
        // 1. Vector search (top 2k candidates)
        let vectorResults = try vectorSearch(queryEmbedding: queryEmbedding, k: k * 2)

        // 2. Full-text search (top 2k candidates)
        let ftsResults = try fullTextSearch(query: queryText, limit: k * 2)

        // 3. Merge scores — normalize and combine
        var scores: [String: Double] = [:]

        // Vector scores (cosine distance → similarity: lower distance = better)
        let maxVecDist = vectorResults.map(\.distance).max() ?? 1.0
        for result in vectorResults {
            let similarity = 1.0 - (result.distance / max(maxVecDist, 0.001))
            scores[result.chunkID, default: 0] += similarity * 0.7
        }

        // FTS scores (rank is negative; more negative = more relevant)
        let minRank = ftsResults.map(\.rank).min() ?? -1.0
        for result in ftsResults {
            let rawRelevance: Double
            if result.rank <= 0 && minRank < 0 {
                rawRelevance = result.rank / minRank
            } else {
                rawRelevance = 0
            }
            let relevance = min(1.0, max(0.0, rawRelevance))
            scores[result.chunkID, default: 0] += relevance * 0.3
        }

        // 4. Filter by minimum score, sort by combined score, take top k
        let topEntries = scores
            .filter { $0.value >= minScore }
            .sorted { $0.value > $1.value }
            .prefix(k)
        let topIDs = topEntries.map(\.key)
        let scoreMap = Dictionary(uniqueKeysWithValues: topEntries.map { ($0.key, $0.value) })

        // 5. Fetch full chunk data
        guard !topIDs.isEmpty else { return [] }
        let placeholders = topIDs.map { _ in "?" }.joined(separator: ", ")
        let sql = "SELECT id, title, summary, content, document_type, slide_number, source_path, created_at FROM chunks WHERE id IN (\(placeholders))"

        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        for (i, id) in topIDs.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        var scoredChunks: [ScoredChunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunk = Chunk(
                id: columnText(stmt!, 0),
                title: columnText(stmt!, 1),
                summary: columnTextOptional(stmt!, 2),
                content: columnText(stmt!, 3),
                documentType: columnTextOptional(stmt!, 4),
                slideNumber: sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 5)) : nil,
                sourcePath: columnText(stmt!, 6),
                createdAt: dateFormatter.date(from: columnText(stmt!, 7)) ?? .now
            )
            let score = scoreMap[chunk.id] ?? 0
            scoredChunks.append(ScoredChunk(chunk: chunk, relevanceScore: score))
        }

        // Re-sort by combined score (highest first)
        scoredChunks.sort { $0.relevanceScore > $1.relevanceScore }

        return scoredChunks
    }

    // MARK: - Document Listing (for Pin Documents)

    /// Returns all indexed documents, ordered by file name.
    func listDocuments() throws -> [IndexedDocument] {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        let sql = "SELECT id, file_name, file_path, document_type, chunk_count, indexed_at, file_size FROM documents ORDER BY file_name"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        var docs: [IndexedDocument] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let docType = IndexedDocument.DocumentType(fromExtension: columnText(stmt!, 3))
            docs.append(IndexedDocument(
                id: columnText(stmt!, 0),
                fileName: columnText(stmt!, 1),
                filePath: columnText(stmt!, 2),
                documentType: docType,
                chunkCount: Int(sqlite3_column_int64(stmt, 4)),
                indexedAt: dateFormatter.date(from: columnText(stmt!, 5)) ?? .now,
                fileSize: sqlite3_column_int64(stmt, 6)
            ))
        }
        return docs
    }

    /// Fetches chunks belonging to a specific document (by document_id).
    /// Used by the "pin documents" feature to manually include a document's chunks in context.
    func chunksForDocument(documentID: String) throws -> [Chunk] {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        let sql = "SELECT id, title, summary, content, document_type, slide_number, source_path, created_at FROM chunks WHERE document_id = ? ORDER BY created_at"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(stmt, 1, documentID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var chunks: [Chunk] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            chunks.append(Chunk(
                id: columnText(stmt!, 0),
                title: columnText(stmt!, 1),
                summary: columnTextOptional(stmt!, 2),
                content: columnText(stmt!, 3),
                documentType: columnTextOptional(stmt!, 4),
                slideNumber: sqlite3_column_type(stmt, 5) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 5)) : nil,
                sourcePath: columnText(stmt!, 6),
                createdAt: dateFormatter.date(from: columnText(stmt!, 7)) ?? .now
            ))
        }
        return chunks
    }

    /// Runs the given block inside a transaction. Rolls back on error.
    func performTransaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN TRANSACTION")
        do {
            let result = try block()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Helpers

    private func embeddingToBlob(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        }
    }

    private func execute(_ sql: String, bindings: [SQLiteBinding] = []) throws {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        if bindings.isEmpty {
            var errMsg: UnsafeMutablePointer<CChar>?
            let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
            guard rc == SQLITE_OK else {
                let msg = errMsg.flatMap { String(cString: $0) } ?? "Error code \(rc)"
                errMsg.flatMap { sqlite3_free($0) }
                throw DatabaseError.queryFailed("\(msg) — SQL: \(sql.prefix(100))")
            }
        } else {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            for (i, binding) in bindings.enumerated() {
                bind(stmt: stmt!, index: Int32(i + 1), value: binding)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func query<T>(_ sql: String, bindings: [SQLiteBinding] = [], mapper: (OpaquePointer) -> T) throws -> [T] {
        guard let db else { throw DatabaseError.connectionFailed("No connection") }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }

        for (i, binding) in bindings.enumerated() {
            bind(stmt: stmt!, index: Int32(i + 1), value: binding)
        }

        var results: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(mapper(stmt!))
        }
        return results
    }

    private func bind(stmt: OpaquePointer, index: Int32, value: SQLiteBinding) {
        switch value {
        case .null:
            sqlite3_bind_null(stmt, index)
        case .int(let v):
            sqlite3_bind_int64(stmt, index, v)
        case .double(let v):
            sqlite3_bind_double(stmt, index, v)
        case .text(let v):
            sqlite3_bind_text(stmt, index, v, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case .blob(let data):
            data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(stmt, index, buffer.baseAddress, Int32(buffer.count),
                                 unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    private func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(stmt, index).flatMap { String(cString: $0) } ?? ""
    }

    private func columnTextOptional(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_text(stmt, index).flatMap { String(cString: $0) }
    }
}

// MARK: - Binding Type

enum SQLiteBinding: Sendable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}
