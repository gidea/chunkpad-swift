import SwiftUI

/// A circular icon button with Liquid Glass styling.
/// Use for toolbar actions, expand/collapse toggles, and small interactive controls.
///
/// Usage:
///   GlassIconButton(systemName: "chevron.down") { doSomething() }
///   GlassIconButton(systemName: "xmark", size: 28) { dismiss() }
struct GlassIconButton: View {
    let systemName: String
    var size: CGFloat = 32
    let action: () -> Void

    private static let iconFont: Font = .system(size: 14, weight: .semibold)

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Self.iconFont)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .contentShape(Circle())
    }
}
