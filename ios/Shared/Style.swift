import SwiftUI

/// Design pieces shared by the iPhone and the Watch.
///
/// Helix's identity is one idea: the Today screen and the Watch face take the colour of the
/// day's readiness, so the answer is visible before anything is read. Everything else stays
/// quiet. The tokens mirror the `:root` block in `prototype/index.html`.
enum Palette {
    static let go = Color(hex: 0x23C16B)
    static let steady = Color(hex: 0xFFB21E)
    static let rest = Color(hex: 0x9B8CFF)
    /// Text on any flood colour, in both themes.
    static let onFlood = Color(hex: 0x111513)
    /// The action colour as it appears on dark surfaces (the Watch is always dark).
    static let actionOnDark = Color(hex: 0x7086FF)

    static func flood(for band: Readiness.Band) -> Color {
        switch band {
        case .primed: go
        case .steady: steady
        case .recover: rest
        }
    }

    static func flood(forScore score: Int) -> Color { flood(for: Readiness.Band(score: score)) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// One family, SF Pro, used at several widths, the way the prototype uses Archivo.
extension Font {
    /// The readiness number: compressed and heavy.
    static func score(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy).width(.compressed) }
    /// Screen titles, verdicts and big figures.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight).width(.condensed) }
    /// Section titles.
    static let sectionTitle = Font.system(size: 18, weight: .bold).width(.condensed)
    /// Numbers that line up in columns. Tabular figures, not a monospaced face.
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight).monospacedDigit() }
}
