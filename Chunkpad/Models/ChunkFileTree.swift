import Foundation
import SwiftUI

// MARK: - Chunk Embedding Status

/// Derived embedding status for a single chunk.
/// Computed from `isIncluded` + membership in `embeddedChunkIDs`.
enum ChunkEmbeddingStatus: Sendable, Equatable {
    /// Embedded in the vector DB and currently included.
    case embedded
    /// Included for embedding but not yet in the vector DB.
    case pending
    /// User toggled this chunk off (will not be embedded).
    case excluded
    // case stale — deferred to task 2.5

    var systemImage: String {
        switch self {
        case .embedded: return "checkmark.circle.fill"
        case .pending:  return "clock.circle.fill"
        case .excluded: return "circle"
        }
    }

    var color: Color {
        switch self {
        case .embedded: return .green
        case .pending:  return .orange
        case .excluded: return .secondary
        }
    }

    var label: String {
        switch self {
        case .embedded: return "Embedded"
        case .pending:  return "Pending"
        case .excluded: return "Excluded"
        }
    }
}

/// Aggregate embedding status for a file (all its chunks).
enum FileEmbeddingStatus: Sendable, Equatable {
    /// All included chunks are embedded.
    case allEmbedded
    /// Some included chunks are embedded, some are pending.
    case partiallyEmbedded
    /// No chunks are embedded (either all pending or all excluded).
    case noneEmbedded
    // case hasStale — deferred to task 2.5

    var dotColor: Color {
        switch self {
        case .allEmbedded:       return .green
        case .partiallyEmbedded: return .orange
        case .noneEmbedded:      return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .allEmbedded:       return "circle.fill"
        case .partiallyEmbedded: return "circle.bottomhalf.filled"
        case .noneEmbedded:      return "circle"
        }
    }
}

// MARK: - Reviewable Chunk

/// A chunk with stable id, include/exclude state, and embedding status for the vector DB.
struct ReviewableChunk: Identifiable, Sendable {
    let id: String
    let processedChunk: ProcessedChunk
    var isIncluded: Bool
    var embeddingStatus: ChunkEmbeddingStatus

    init(id: String, processedChunk: ProcessedChunk, isIncluded: Bool = true, embeddingStatus: ChunkEmbeddingStatus = .pending) {
        self.id = id
        self.processedChunk = processedChunk
        self.isIncluded = isIncluded
        self.embeddingStatus = embeddingStatus
    }

    /// Stable identifier: "{filePath}::chunk_{index}"
    static func chunkID(filePath: String, index: Int) -> String {
        "\(filePath)::chunk_\(index)"
    }
}

// MARK: - Chunk File Tree Node

enum ChunkFileTreeNode: Identifiable, Sendable {
    case folder(ChunkFolderNode)
    case file(ChunkFileNode)

    var id: String {
        switch self {
        case .folder(let n): return "folder:\(n.path)"
        case .file(let n): return "file:\(n.fileInfo.fileURL.path)"
        }
    }

    var displayName: String {
        switch self {
        case .folder(let n): return n.name
        case .file(let n): return n.fileInfo.fileName
        }
    }
}

struct ChunkFolderNode: Sendable {
    let name: String
    let path: String
    var children: [ChunkFileTreeNode]
}

struct ChunkFileNode: Identifiable, Sendable {
    let fileInfo: ChunkFileInfo

    var id: String { fileInfo.id.uuidString }
}

// MARK: - Chunk File Tree

/// Root tree of chunk markdown files, built from discovery.
struct ChunkFileTree: Sendable {
    let rootFolder: ChunkFolderNode

    init(chunkFiles: [ChunkFileInfo], chunksRootURL: URL) {
        self.rootFolder = Self.buildTree(from: chunkFiles, chunksRoot: chunksRootURL)
    }

    private static func buildTree(from chunkFiles: [ChunkFileInfo], chunksRoot: URL) -> ChunkFolderNode {
        let rootPath = chunksRoot.standardized.path

        var folderChildren: [String: [String]] = [:] // path -> child names
        var fileByPath: [String: ChunkFileInfo] = [:]

        for info in chunkFiles {
            let chunkPath = info.fileURL.standardized.path
            guard chunkPath.hasPrefix(rootPath) else { continue }
            let relative = String(chunkPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let components = (relative as NSString).pathComponents

            if components.count == 1 {
                fileByPath[relative] = info
            } else {
                let first = components[0]
                if folderChildren[first] == nil {
                    folderChildren[first] = []
                }
                if components.count == 2 {
                    fileByPath[relative] = info
                } else {
                    var current = first
                    for i in 1..<(components.count - 1) {
                        let next = (current as NSString).appendingPathComponent(components[i])
                        if folderChildren[next] == nil {
                            folderChildren[next] = []
                        }
                        if var children = folderChildren[current], !children.contains(next) {
                            children.append(next)
                            folderChildren[current] = children
                        }
                        current = next
                    }
                    fileByPath[relative] = info
                }
            }
        }

        return buildNode(name: (rootPath as NSString).lastPathComponent, path: rootPath, relativePrefix: "", chunkFiles: chunkFiles, rootPath: rootPath)
    }

    private static func buildNode(name: String, path: String, relativePrefix: String, chunkFiles: [ChunkFileInfo], rootPath: String) -> ChunkFolderNode {
        var children: [ChunkFileTreeNode] = []

        var subfolders: [String: [String]] = [:]
        var directFiles: [ChunkFileInfo] = []

        for info in chunkFiles {
            let chunkPath = info.fileURL.standardized.path
            guard chunkPath.hasPrefix(rootPath) else { continue }
            let relative = String(chunkPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard relativePrefix.isEmpty ? !relative.contains("/") : relative.hasPrefix(relativePrefix + "/") else { continue }

            let remainder = relativePrefix.isEmpty ? relative : String(relative.dropFirst(relativePrefix.count + 1))
            let parts = remainder.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

            if parts.count == 1 && !parts[0].isEmpty {
                directFiles.append(info)
            } else if parts.count > 1 {
                let subfolder = parts[0]
                if subfolders[subfolder] == nil {
                    subfolders[subfolder] = []
                }
            }
        }

        for info in directFiles {
            children.append(.file(ChunkFileNode(fileInfo: info)))
        }

        let prefix = relativePrefix.isEmpty ? "" : relativePrefix + "/"
        for (subfolderName, _) in subfolders.sorted(by: { $0.key < $1.key }) {
            let subPath = prefix + subfolderName
            let fullPath = (rootPath as NSString).appendingPathComponent(subPath)
            let subNode = buildNode(name: subfolderName, path: fullPath, relativePrefix: subPath, chunkFiles: chunkFiles, rootPath: rootPath)
            children.append(.folder(subNode))
        }

        children.sort { n1, n2 in
            let (isFolder1, isFolder2) = (n1.isFolder, n2.isFolder)
            if isFolder1 != isFolder2 { return isFolder1 }
            return n1.displayName.localizedCaseInsensitiveCompare(n2.displayName) == .orderedAscending
        }

        return ChunkFolderNode(name: name, path: path, children: children)
    }
}

extension ChunkFileTreeNode {
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    /// Children for OutlineGroup; nil for file nodes.
    var children: [ChunkFileTreeNode]? {
        if case .folder(let n) = self { return n.children }
        return nil
    }
}
