import Foundation

// MARK: - FeedbackType

/// The user's persistent signal on a chunk's retrieval quality.
///
/// Applied as a score multiplier in `hybridSearch` after the 70/30 vector+FTS
/// score is computed:
/// - boost:   1.5× (capped at 1.0 to avoid artificial inflation)
/// - neutral: 1.0× (no change — default for all chunks with no record)
/// - hide:    0.5× (dampened but still retrievable when highly relevant)
enum FeedbackType: String, Codable, Sendable, CaseIterable {
    case boost   = "boost"
    case hide    = "hide"
    case neutral = "neutral"

    /// Score multiplier applied to the hybrid relevance score.
    var multiplier: Double {
        switch self {
        case .boost:   return 1.5
        case .neutral: return 1.0
        case .hide:    return 0.5
        }
    }

    var displayName: String {
        switch self {
        case .boost:   return "Boosted"
        case .neutral: return "Neutral"
        case .hide:    return "Hidden"
        }
    }
}

// MARK: - ChunkFeedback

/// A persisted feedback record for a single chunk.
///
/// Feedback survives re-indexing because it is keyed on `(sourcePath, titleHash)`
/// in addition to `chunkId`. When a document is re-processed and chunks get new
/// UUIDs, the re-matching logic in `DatabaseService` updates `chunkId` to the new
/// UUID using the stable `(sourcePath, titleHash)` key.
struct ChunkFeedback: Identifiable, Sendable {
    let id: String
    let chunkId: String

    /// `chunks.source_path` — used for re-matching after re-index.
    let sourcePath: String

    /// SHA-256 hex digest of `chunk.title` — stable identifier for re-matching.
    let titleHash: String

    let feedbackType: FeedbackType
    let multiplier: Double
    let createdAt: Date
    let updatedAt: Date
}
