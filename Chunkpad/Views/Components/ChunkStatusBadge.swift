import SwiftUI

/// A compact status indicator for chunk embedding status.
/// Renders as a colored SF Symbol, optionally with a text label.
///
/// Usage:
///   ChunkStatusBadge(status: .embedded)
///   ChunkStatusBadge(status: .pending, showLabel: true)
struct ChunkStatusBadge: View {
    let status: ChunkEmbeddingStatus
    var showLabel: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
                .font(.caption2)
            if showLabel {
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(status.color)
            }
        }
    }
}
