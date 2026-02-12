import Foundation
import SQLite3

// MARK: - Conversation DB Errors

enum ConversationDatabaseError: LocalizedError, Sendable {
    case connectionFailed(String)
    case queryFailed(String)
    case schemaFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Chat DB connection failed: \(msg)"
        case .queryFailed(let msg): return "Chat DB query failed: \(msg)"
        case .schemaFailed(let msg): return "Chat DB schema failed: \(msg)"
        }
    }
}

// MARK: - Conversation Database Service

/// Separate SQLite database for conversations and messages only.
/// Uses `chunkpad_chat.db` in Application Support/Chunkpad. No documents, chunks, or embeddings.
actor ConversationDatabaseService {

    static let currentSchemaVersion = 2

    private nonisolated(unsafe) var db: OpaquePointer?
    private let databasePath: String

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Cached date formatters to avoid repeated allocation in hot paths.
    /// nonisolated(unsafe) is safe here: ISO8601DateFormatter is thread-safe for
    /// formatting/parsing once configured, and these are immutable after init.
    nonisolated(unsafe) private static let dateFormatterWithFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let dateFormatterWithoutFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private nonisolated func formatDate(_ date: Date) -> String {
        Self.dateFormatterWithFrac.string(from: date)
    }

    private nonisolated func parseDate(_ s: String) -> Date {
        if let d = Self.dateFormatterWithFrac.date(from: s) { return d }
        return Self.dateFormatterWithoutFrac.date(from: s) ?? Date()
    }

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Chunkpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.databasePath = appSupport.appendingPathComponent("chunkpad_chat.db").path
    }

    init(path: String) {
        self.databasePath = path
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func connect() throws {
        guard db == nil else { return }
        var dbPointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databasePath, &dbPointer, flags, nil)
        guard rc == SQLITE_OK, let dbPointer else {
            let msg = dbPointer.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw ConversationDatabaseError.connectionFailed(msg)
        }
        self.db = dbPointer
        try execute("PRAGMA journal_mode=WAL")
        try createSchema()
        try migrate()
    }

    private func execute(_ sql: String) throws {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        let rc = sqlite3_step(statement)
        // SQLITE_DONE for statements, SQLITE_ROW for PRAGMAs that return results
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func createSchema() throws {
        try execute("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)")

        try execute("""
            CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS messages (
                id TEXT PRIMARY KEY,
                conversation_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                referenced_chunk_ids TEXT DEFAULT '[]',
                FOREIGN KEY (conversation_id) REFERENCES conversations(id)
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id)")
    }

    private func querySchemaVersion() throws -> Int {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let sql = "SELECT COALESCE(MAX(version), 0) FROM schema_version"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        var result = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            result = Int(sqlite3_column_int64(statement, 0))
        }
        return result
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
                break
            case 2:
                try execute("CREATE INDEX IF NOT EXISTS idx_messages_conversation_timestamp ON messages(conversation_id, timestamp)")
            default:
                break
            }
            guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
            let sql = "INSERT OR REPLACE INTO schema_version (version) VALUES (?)"
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            sqlite3_bind_int64(statement, 1, Int64(version))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Creates a new conversation and returns its id.
    func createConversation(title: String) throws -> String {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let id = UUID().uuidString
        let now = formatDate(Date())
        let sql = "INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, id, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 2, title, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 3, now, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 4, now, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return id
    }

    func updateConversation(id: String, title: String, updatedAt: Date) throws {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let updated = formatDate(updatedAt)
        let sql = "UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, title, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 2, updated, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 3, id, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchConversations(limit: Int = 100) throws -> [Conversation] {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let sql = "SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC LIMIT ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_int64(statement, 1, Int64(limit))
        var result: [Conversation] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let title = String(cString: sqlite3_column_text(statement, 1))
            let createdAtStr = String(cString: sqlite3_column_text(statement, 2))
            let updatedAtStr = String(cString: sqlite3_column_text(statement, 3))
            let createdAt = parseDate(createdAtStr)
            let updatedAt = parseDate(updatedAtStr)
            result.append(Conversation(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt))
        }
        return result
    }

    func insertMessage(_ message: Message, conversationId: String) throws {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let refIdsData = try? JSONEncoder().encode(message.referencedChunkIDs)
        let refIdsJson = refIdsData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let ts = formatDate(message.timestamp)
        let sql = "INSERT INTO messages (id, conversation_id, role, content, timestamp, referenced_chunk_ids) VALUES (?, ?, ?, ?, ?, ?)"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, message.id, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 2, conversationId, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 3, message.role.rawValue, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 4, message.content, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 5, ts, -1, Self.sqliteTransient)
        sqlite3_bind_text(statement, 6, refIdsJson, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func fetchMessages(conversationId: String) throws -> [Message] {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        let sql = "SELECT id, role, content, timestamp, referenced_chunk_ids FROM messages WHERE conversation_id = ? ORDER BY timestamp ASC"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, conversationId, -1, Self.sqliteTransient)
        var result: [Message] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let roleStr = String(cString: sqlite3_column_text(statement, 1))
            let content = String(cString: sqlite3_column_text(statement, 2))
            let tsStr = String(cString: sqlite3_column_text(statement, 3))
            let refIdsPtr = sqlite3_column_text(statement, 4)
            let refIdsJson = refIdsPtr.map { String(cString: $0) } ?? "[]"
            let timestamp = parseDate(tsStr)
            let role = Message.Role(rawValue: roleStr) ?? .user
            let refIds: [String] = (try? JSONDecoder().decode([String].self, from: Data(refIdsJson.utf8))) ?? []
            result.append(Message(id: id, role: role, content: content, timestamp: timestamp, referencedChunkIDs: refIds))
        }
        return result
    }

    func deleteConversation(id: String) throws {
        guard let db else { throw ConversationDatabaseError.connectionFailed("No connection") }
        try execute("BEGIN TRANSACTION")
        do {
            for sql in ["DELETE FROM messages WHERE conversation_id = ?", "DELETE FROM conversations WHERE id = ?"] {
                var statement: OpaquePointer?
                defer { sqlite3_finalize(statement) }
                guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
                }
                sqlite3_bind_text(statement, 1, id, -1, Self.sqliteTransient)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw ConversationDatabaseError.queryFailed(String(cString: sqlite3_errmsg(db)))
                }
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
