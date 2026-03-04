import Foundation

// MARK: - Collection

/// A named group of indexed documents used to scope retrieval.
///
/// Collections are lightweight labels stored in the database — not filesystem
/// folders. A document belongs to at most one collection (`collection_id` on
/// the `documents` table). `nil` means "Uncategorized" (included in all searches
/// by default).
///
/// When a chat session is scoped to a collection, `hybridSearch` adds a
/// `WHERE documents.collection_id = ?` filter so only that collection's chunks
/// are considered for context.
struct Collection: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let createdAt: Date

    /// Optional accent color stored as a CSS hex string, e.g. `"#FF6B35"`.
    /// Used to tint the collection badge on `ChunkPreview` cards.
    let color: String?

    /// Total number of documents assigned to this collection.
    /// Computed via LEFT JOIN in `fetchCollections()` — not stored in the table.
    var documentCount: Int
}
