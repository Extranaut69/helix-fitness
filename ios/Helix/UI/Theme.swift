import SwiftUI

enum Theme {
    static let hull = Color(red: 0.043, green: 0.067, blue: 0.110)
    static let panel = Color(red: 0.067, green: 0.102, blue: 0.157)
    static let line = Color(red: 0.133, green: 0.192, blue: 0.290)
    static let mute = Color(red: 0.522, green: 0.576, blue: 0.667)
    static let ice = Color(red: 0.498, green: 0.878, blue: 1.0)
    static let protein = Color(red: 1.0, green: 0.541, blue: 0.420)
    static let carbs = Color(red: 1.0, green: 0.812, blue: 0.361)
    static let fat = Color(red: 0.725, green: 0.608, blue: 1.0)
    static let good = Color(red: 0.357, green: 0.890, blue: 0.643)
    static let warn = Color(red: 1.0, green: 0.710, blue: 0.278)
    static let bad = Color(red: 1.0, green: 0.365, blue: 0.451)

    static func color(for band: Readiness.Band) -> Color {
        switch band {
        case .primed: good
        case .steady: warn
        case .recover: bad
        }
    }

    static func scoreColor(_ v: Double) -> Color { v >= 70 ? good : v >= 50 ? warn : bad }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
    }
}

struct Eyebrow: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.mute)
    }
}

extension Font {
    static func data(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
