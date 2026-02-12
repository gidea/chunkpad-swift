import XCTest
@testable import Chunkpad

final class ConversationDatabaseServiceTests: XCTestCase {

    private func makeTempDB() -> ConversationDatabaseService {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_chat_\(UUID().uuidString).db").path
        return ConversationDatabaseService(path: path)
    }

    // MARK: - Migration Tests

    func testFreshDBMigrates() async throws {
        let db = makeTempDB()
        try await db.connect()
        // If we got here without crashing, migrations from 0 → latest succeeded
    }

    func testIdempotentConnect() async throws {
        let db = makeTempDB()
        try await db.connect()
        // Second connect should be a no-op (guard db == nil returns early)
        try await db.connect()
    }

    func testSeparateInstancesMigrateOnce() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_chat_\(UUID().uuidString).db").path
        let db1 = ConversationDatabaseService(path: path)
        try await db1.connect()

        // Second instance on same file — migrations should skip (already at latest)
        let db2 = ConversationDatabaseService(path: path)
        try await db2.connect()
    }

    // MARK: - CRUD Tests

    func testCreateAndFetchConversation() async throws {
        let db = makeTempDB()
        try await db.connect()

        let id = try await db.createConversation(title: "Test Chat")
        let conversations = try await db.fetchConversations()

        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, id)
        XCTAssertEqual(conversations.first?.title, "Test Chat")
    }

    func testInsertAndFetchMessages() async throws {
        let db = makeTempDB()
        try await db.connect()

        let convId = try await db.createConversation(title: "Chat")
        let msg = Message(role: .user, content: "Hello", referencedChunkIDs: ["chunk-1"])
        try await db.insertMessage(msg, conversationId: convId)

        let messages = try await db.fetchMessages(conversationId: convId)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.content, "Hello")
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.referencedChunkIDs, ["chunk-1"])
    }

    func testDeleteConversationRemovesMessages() async throws {
        let db = makeTempDB()
        try await db.connect()

        let convId = try await db.createConversation(title: "To Delete")
        let msg = Message(role: .user, content: "Bye")
        try await db.insertMessage(msg, conversationId: convId)

        try await db.deleteConversation(id: convId)

        let conversations = try await db.fetchConversations()
        let messages = try await db.fetchMessages(conversationId: convId)

        XCTAssertTrue(conversations.isEmpty)
        XCTAssertTrue(messages.isEmpty)
    }

    func testFetchConversationsRespectsLimit() async throws {
        let db = makeTempDB()
        try await db.connect()

        for i in 1...5 {
            _ = try await db.createConversation(title: "Chat \(i)")
        }

        let limited = try await db.fetchConversations(limit: 3)
        XCTAssertEqual(limited.count, 3)

        let all = try await db.fetchConversations(limit: 100)
        XCTAssertEqual(all.count, 5)
    }
}
