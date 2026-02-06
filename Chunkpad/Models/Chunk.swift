import Foundation

struct Chunk: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let title: String
    let summary: String?
    let content: String
    let documentType: String?
    let slideNumber: Int?
    let sourcePath: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        summary: String? = nil,
        content: String,
        documentType: String? = nil,
        slideNumber: Int? = nil,
        sourcePath: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.content = content
        self.documentType = documentType
        self.slideNumber = slideNumber
        self.sourcePath = sourcePath
        self.createdAt = createdAt
    }
}
