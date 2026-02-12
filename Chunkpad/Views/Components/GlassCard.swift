import SwiftUI

/// A reusable card component with Liquid Glass styling.
/// Uses centralized design tokens for consistent appearance.
///
/// Usage:
///   GlassCard { Text("Hello") }
///   GlassCard(cornerRadius: GlassTokens.Radius.element) { ChunkContent() }
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = GlassTokens.Radius.card,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(GlassTokens.Padding.card)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
