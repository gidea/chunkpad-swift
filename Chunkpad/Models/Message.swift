import Foundation

struct Message: Identifiable, Codable, Sendable {
    let id: String
    let role: Role
    var content: String
    let timestamp: Date
    var referencedChunkIDs: [String]

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        timestamp: Date = .now,
        referencedChunkIDs: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.referencedChunkIDs = referencedChunkIDs
    }
}
