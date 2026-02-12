import SwiftUI

/// A capsule-shaped Liquid Glass element for tags, status indicators, and compact labels.
///
/// Usage:
///   GlassPill { Label("Slide 3", systemImage: "rectangle.on.rectangle") }
///   GlassPill { Text("PDF") }
struct GlassPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .glassEffect(.regular, in: .capsule)
    }
}
