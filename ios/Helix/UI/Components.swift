import SwiftUI
import Charts

// MARK: - Readiness field

/// One readiness signal in everyday words: "Sleep, 7.5 h, Good".
struct ReadinessSignal: Identifiable {
    var label: String
    var value: String
    var status: String
    var id: String { label }
}

/// Today's opening field. The whole block takes the colour of the readiness band, so the answer
/// shows before anything is read. The score is labelled, the verdict is one plain sentence, and the
/// three signals behind it use everyday words. On appear the number counts up: the app's one motion.
struct ReadinessField<Accessory: View>: View {
    var readiness: Readiness
    var signals: [ReadinessSignal]
    var headline: String
    var detail: String
    @ViewBuilder var accessory: Accessory

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                accessory
            }
            HStack(alignment: .bottom, spacing: 12) {
                Text("\(shown ?? readiness.score)")
                    .font(.score(132))
                    .tracking(-3)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(shown ?? readiness.score)))
                    .padding(.leading, -4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Readiness").font(.system(size: 17, weight: .bold))
                    Text("out of 100").font(.system(size: 15))
                }
                .padding(.bottom, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Readiness \(readiness.score) out of 100")
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.display(32, weight: .heavy))
                Text(detail).font(.system(size: 16)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(signals) { s in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.label).font(.system(size: 13))
                        Text(s.value).font(.system(size: 18, weight: .bold).width(.condensed).monospacedDigit())
                        Text(s.status).font(.system(size: 13, weight: .semibold))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .foregroundStyle(Theme.onFlood)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: Theme.floodRadius, bottomTrailingRadius: Theme.floodRadius, style: .continuous)
                .fill(Theme.flood(for: readiness.band))
                .padding(.top, -600)   // runs up under the status bar and any overscroll
        }
        .onAppear(perform: countUp)
        .onChange(of: readiness.score) { _, _ in countUp() }
    }

    /// The real score is always what shows at rest; the count only plays when motion is allowed.
    private func countUp() {
        guard !reduceMotion else { shown = nil; return }
        shown = 0
        withAnimation(.easeOut(duration: 0.9)) { shown = readiness.score }
    }
}

// MARK: - Food

struct MacroPart: Identifiable {
    var name: String
    var eaten: Double
    var target: Double
    var color: Color
    var id: String { name }
}

/// One labelled bar per macro: "Protein  31 of 156 g".
struct MacroBars: View {
    var parts: [MacroPart]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(parts) { p in
                VStack(spacing: 6) {
                    HStack {
                        Text(p.name).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        if p.eaten > p.target * 1.05 {
                            Text("\(Int((p.eaten - p.target).rounded())) g over").font(.figure(15))
                        } else {
                            (Text("\(Int(p.eaten.rounded()))").font(.figure(15))
                                + Text(" of \(Int(p.target)) g").font(.figure(15, weight: .regular)).foregroundColor(Theme.ink2))
                        }
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(p.color.opacity(0.18))
                            Capsule().fill(p.color).frame(width: geo.size.width * min(1, max(0, p.eaten / max(p.target, 1))))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.ink)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Timeline

/// A row on the day's timeline (meals eaten, meals planned). A filled dot is done; a hollow one is planned.
struct TimelineRow<Content: View, Trailing: View>: View {
    var time: String
    var planned = false
    var isFirst = false
    var isLast = false
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time).font(.figure(13, weight: .regular)).foregroundStyle(Theme.ink2)
                .frame(width: 42, alignment: .leading).padding(.top, 1)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.leading, 22)
            .padding(.bottom, 18)
            .background(alignment: .topLeading) { rail }
        }
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.rule).frame(width: 2)
                .frame(maxHeight: isLast ? 7 : .infinity, alignment: .top)
                .padding(.top, isFirst ? 7 : 0)
            Circle()
                .fill(planned ? Theme.fog : Theme.ink)
                .overlay { if planned { Circle().strokeBorder(Theme.ink3, lineWidth: 2) } }
                .frame(width: 12, height: 12)
                .background(Circle().fill(Theme.fog).padding(-3))
                .padding(.top, 5)
        }
        .frame(width: 12, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Weight chart

struct WeightTrendChart: View {
    var points: [(date: Date, kg: Double)]

    var body: some View {
        VStack(spacing: 4) {
            Chart {
                ForEach(points.indices, id: \.self) { i in
                    AreaMark(x: .value("Day", points[i].date), y: .value("kg", points[i].kg))
                        .foregroundStyle(Theme.wash)
                    LineMark(x: .value("Day", points[i].date), y: .value("kg", points[i].kg))
                        .foregroundStyle(Theme.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
                if let last = points.last {
                    PointMark(x: .value("Day", last.date), y: .value("kg", last.kg))
                        .foregroundStyle(Theme.ink)
                        .symbolSize(80)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.rule)
                    AxisValueLabel {
                        Text("\(value.as(Double.self) ?? 0, specifier: "%.0f") kg").font(.system(size: 11)).foregroundStyle(Theme.ink3)
                    }
                }
            }
            .frame(height: 96)
            HStack {
                Text("3 weeks ago")
                Spacer()
                Text("Today")
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(points.isEmpty ? "No weight data" : String(format: "Weight over 3 weeks, now %.1f kilograms", points.last!.kg))
    }
}

// MARK: - Headers

struct ScreenHeader<Accessory: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(34, weight: .heavy)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.ink2) }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }
}

extension ScreenHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle) { EmptyView() } }
}

struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.sectionTitle).foregroundStyle(Theme.ink)
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Small parts

/// Initials in a ring; it takes the colour of whatever it sits on.
struct AvatarButton: View {
    var initials: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(initials).font(.system(size: 13, weight: .bold).width(.condensed))
                .frame(width: 38, height: 38)
                .overlay(Circle().strokeBorder(lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch person or edit profile")
    }
}

/// A raised surface, used only for the one thing on a screen that should stand apart (a meal total, a product).
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}

struct HelixButtonStyle: ButtonStyle {
    enum Kind { case primary, quiet }
    var kind: Kind
    var small = false
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let style: HelixButtonStyle
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.small ? 10 : Theme.controlRadius, style: .continuous)
            configuration.label
                .font(.system(size: style.small ? 13 : 15, weight: .semibold))
                .padding(.horizontal, style.small ? 12 : 16)
                .padding(.vertical, style.small ? 7 : 12)
                .frame(maxWidth: style.fill ? .infinity : nil)
                .foregroundStyle(style.kind == .primary ? Theme.onAction : Theme.ink)
                .background(style.kind == .primary ? Theme.action : Color.clear, in: shape)
                .overlay { if style.kind == .quiet { shape.strokeBorder(Theme.rule, lineWidth: 1.5) } }
                .contentShape(shape)
                .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
        }
    }
}

extension ButtonStyle where Self == HelixButtonStyle {
    static func helix(_ kind: HelixButtonStyle.Kind, small: Bool = false, fill: Bool = false) -> HelixButtonStyle {
        HelixButtonStyle(kind: kind, small: small, fill: fill)
    }
}

/// A suggestion the user can tap, such as a question for the coach.
struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Footnote that says where sample or estimated values come from.
struct SourceNote: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
