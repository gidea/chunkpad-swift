import SwiftUI

/// Sidebar showing the chunk file tree hierarchy with per-item status badges.
struct ChunkTreeSidebarView: View {
    let tree: ChunkFileTree
    @Binding var selectedNodeID: String?
    var viewModel: IndexingViewModel
    var onEmbedApproved: () -> Void

    var body: some View {
        List(selection: $selectedNodeID) {
            OutlineGroup(tree.rootFolder.children, children: \.children) { node in
                switch node {
                case .folder(let n):
                    // Per-folder aggregate status badge
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(n.name)
                        Spacer()
                        let status = viewModel.folderAggregateStatus(for: n)
                        Image(systemName: status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(status.dotColor)
                    }
                case .file(let n):
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                        Text(n.fileInfo.fileName)
                        Spacer()
                        let status = viewModel.fileAggregateStatus(for: n.fileInfo)
                        Image(systemName: status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(status.dotColor)
                    }
                    .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chunk Files")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let approved = viewModel.approvedChunksForEmbed().count
                Button("Embed Selected (\(approved))") {
                    onEmbedApproved()
                }
                .disabled(approved == 0 || viewModel.isIndexing)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
