import SwiftUI

/// A reusable card component with Liquid Glass styling.
/// Per Liquid Glass skill: apply .glassEffect() AFTER layout/visual modifiers.
struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
