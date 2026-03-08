import SwiftUI

extension Color {
    /// Parses a CSS hex color string like `"#FF6B35"` or `"FF6B35"` into a SwiftUI `Color`.
    /// Returns nil if the string is nil or not a valid 6-character hex color.
    init?(hex: String?) {
        guard let hex else { return nil }
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        self.init(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8)  & 0xFF) / 255,
            blue:  Double(value         & 0xFF) / 255
        )
    }
}
