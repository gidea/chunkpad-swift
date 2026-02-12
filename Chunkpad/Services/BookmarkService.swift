import Foundation

// MARK: - Bookmark Errors

enum BookmarkError: LocalizedError, Sendable {
    case creationFailed(String)
    case resolutionFailed(String)
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "Bookmark creation failed: \(msg)"
        case .resolutionFailed(let msg): return "Bookmark resolution failed: \(msg)"
        case .accessDenied(let msg): return "Folder access denied: \(msg)"
        }
    }
}

// MARK: - Bookmark Service

/// Manages security-scoped bookmarks for sandboxed folder access.
/// Bookmarks allow the app to re-access user-selected folders after relaunch
/// without requiring the user to re-select them via NSOpenPanel.
struct BookmarkService: Sendable {

    /// Creates a security-scoped bookmark for the given URL.
    /// Call this immediately after the user selects a folder via NSOpenPanel.
    func createBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw BookmarkError.creationFailed(error.localizedDescription)
        }
    }

    /// Resolves a security-scoped bookmark back to a URL.
    /// Returns the resolved URL and whether the bookmark is stale (needs refresh).
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            throw BookmarkError.resolutionFailed(error.localizedDescription)
        }
    }

    /// Begins security-scoped access to the given URL.
    /// Returns `true` if access was granted.
    func startAccessing(url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    /// Ends security-scoped access to the given URL.
    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    /// Convenience: resolves bookmark, starts access, and optionally refreshes stale bookmark.
    /// Returns the resolved URL and refreshed bookmark data (if stale).
    func resolveAndAccess(_ bookmarkData: Data) throws -> (url: URL, refreshedBookmark: Data?) {
        let (url, isStale) = try resolveBookmark(bookmarkData)

        guard startAccessing(url: url) else {
            throw BookmarkError.accessDenied("Security-scoped access denied for \(url.lastPathComponent)")
        }

        var refreshedBookmark: Data?
        if isStale {
            // Try to create a fresh bookmark while we have access
            refreshedBookmark = try? createBookmark(for: url)
        }

        return (url, refreshedBookmark)
    }
}
