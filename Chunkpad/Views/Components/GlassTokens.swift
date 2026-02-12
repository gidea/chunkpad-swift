import SwiftUI

/// Centralized design tokens for the Liquid Glass design system.
/// Only contains values that are genuinely reused across multiple files.
/// Single-use constants belong in their owning component.
enum GlassTokens {

    // MARK: - Corner Radii

    enum Radius {
        /// Cards, panels, content containers, input bar
        static let card: CGFloat = 20
        /// Small elements like chunk previews, error banners
        static let element: CGFloat = 14
        /// Input fields and small containers
        static let input: CGFloat = 16
    }

    // MARK: - Spacing

    enum Spacing {
        /// Default spacing inside a GlassEffectContainer
        static let containerDefault: CGFloat = 8
        /// No spacing (e.g., stacked input bar + chunks bar)
        static let containerFlush: CGFloat = 0
    }

    // MARK: - Padding

    enum Padding {
        /// Card / surface inner padding (used by GlassCard, IndexingProgressView)
        static let card = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        /// Element-level items (chunk previews, error banners)
        static let element = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    }
}
