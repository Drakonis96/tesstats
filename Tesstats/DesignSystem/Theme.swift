import SwiftUI

// MARK: - Color hex helpers

extension Color {
    /// Create a color from a 24-bit RGB hex value, e.g. `Color(hex: 0xB30333)`.
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }

    /// Create a color from a hex string such as `"B30333"` or `"#B30333"`.
    init(hex string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt32(s, radix: 16) ?? 0
        self.init(hex: value)
    }
}

// MARK: - Brand palette

/// Central, minimal, premium-dark palette. Pure black background, crimson accent.
enum Brand {
    /// `#B30333` — the brand crimson. Accent for active icons, highlighted values,
    /// charts, the battery ring, charging states and glass tinting.
    static let crimson = Color(hex: 0xB30333)
    static let crimsonBright = Color(hex: 0xE21050)
    static let crimsonDim = Color(hex: 0x7A0526)

    /// Pure black canvas.
    static let background = Color.black
    /// Near-black card surface for dense reading content (never glass).
    static let surface = Color(hex: 0x0E0E10)
    static let elevatedSurface = Color(hex: 0x16161A)
    static let hairline = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.40)

    // Semantic status colors (kept restrained, crimson stays the hero).
    static let online = Color(hex: 0x35C759)
    static let charging = crimson
    static let driving = Color(hex: 0x0A84FF)
    static let asleep = Color(hex: 0x8E8E93)
    static let offline = Color(hex: 0x5A5A60)
    static let warning = Color(hex: 0xFF9F0A)
    static let danger = Color(hex: 0xFF453A)
}

// MARK: - Spacing & radii

enum Metrics {
    static let cardRadius: CGFloat = 22
    static let tightRadius: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let screenPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
}
