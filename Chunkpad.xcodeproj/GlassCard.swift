import SwiftUI

/// A reusable card component with Liquid Glass styling.
///
/// Usage:
///   GlassCard { Text("Hello") }
///   GlassCard(cornerRadius: 16) { ChunkContent() }
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
