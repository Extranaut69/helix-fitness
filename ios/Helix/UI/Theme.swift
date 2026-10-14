import SwiftUI
import UIKit

/// iPhone design tokens. Light and dark values match the prototype; readiness floods live in `Palette`.
enum Theme {
    // Surface and ink
    static let fog = Color(light: 0xEEF0ED, dark: 0x0E1110)
    static let paper = Color(light: 0xFFFFFF, dark: 0x171B19)
    static let ink = Color(light: 0x121614, dark: 0xECEFEC)
    static let ink2 = Color(light: 0x59615C, dark: 0xA0A8A3)
    static let ink3 = Color(light: 0x8A928D, dark: 0x6E7671)
    static let rule = Color(light: 0xD6DBD7, dark: 0x29302C)
    static let wash = ink.opacity(0.06)

    // The one action colour
    static let action = Color(light: 0x2F4BFF, dark: 0x7086FF)
    static let onAction = Color(light: 0xFFFFFF, dark: 0x0B0E0D)

    // Macros
    static let protein = Color(light: 0x2F4BFF, dark: 0x7086FF)
    static let carbs = Color(light: 0x0E9F92, dark: 0x3CCFC0)
    static let fat = Color(light: 0xC98F00, dark: 0xF2C14E)

    // Camera surfaces stay dark in either theme
    static let lens = Color(hex: 0x0B0D0C)
    static let lensInk = Color(hex: 0xF2F4F2)

    static let onFlood = Palette.onFlood
    static func flood(for band: Readiness.Band) -> Color { Palette.flood(for: band) }

    // Spacing and shape. Radius follows importance instead of being the same everywhere.
    static let gutter: CGFloat = 20
    static let sectionGap: CGFloat = 30
    static let floodRadius: CGFloat = 36
    static let panelRadius: CGFloat = 14
    static let controlRadius: CGFloat = 12
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        let l = UIColor(Color(hex: light)), d = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
}
