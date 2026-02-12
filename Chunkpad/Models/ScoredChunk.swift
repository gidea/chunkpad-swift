import Foundation

/// A chunk paired with its hybrid-search relevance score and an include/exclude toggle.
///
/// `Chunk` stays clean for database storage; `ScoredChunk` is the search-result
/// wrapper used in the chat UI so users can see relevance and toggle chunks on/off
/// before (re)generating an LLM response.
struct ScoredChunk: Identifiable, Sendable {
    let chunk: Chunk

    /// Combined hybrid-search score (0.0 – 1.0, higher = more relevant).
    /// 70 % vector similarity + 30 % FTS5 keyword match.
    let relevanceScore: Double

    /// Whether this chunk is included in the LLM context.
    /// Defaults to `true`; users can toggle it off to exclude a chunk.
    var isIncluded: Bool = true

    var id: String { chunk.id }

    /// Convenience: relevance as a rounded percentage string, e.g. "87 %".
    var relevancePercent: String {
        "\(Int((relevanceScore * 100).rounded())) %"
    }
}
