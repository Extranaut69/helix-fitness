import SwiftUI
import Charts

/// Instrument-style readiness ring: tick marks around a gradient progress arc.
struct ReadinessRing: View {
    var score: Int
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach(0..<60, id: \.self) { i in
                Capsule()
                    .fill(Double(i) / 60 * 100 <= Double(score) ? Theme.ice : Theme.line)
                    .frame(width: 1.4, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -size / 2 + 4)
                    .rotationEffect(.degrees(Double(i) * 6))
            }
            Circle().stroke(Theme.line.opacity(0.6), lineWidth: 10).padding(14)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(LinearGradient(colors: [.white.opacity(0.9), Theme.ice], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(14)
                .shadow(color: Theme.ice.opacity(0.5), radius: 6)
            VStack(spacing: 0) {
                Text("\(score)").font(.system(size: size * 0.23, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text("READINESS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.mute)
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.8), value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(score) out of 100")
    }
}

struct MacroBar: View {
    var label: String
    var value: Double
    var target: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(value.rounded()))").font(.data(14)).bold()
                    + Text(" / \(Int(target)) g").font(.data(12)).foregroundColor(Theme.mute)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1, max(0, value / max(target, 1))))
                        .shadow(color: color.opacity(0.5), radius: 5)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var unit: String
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(Theme.mute)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.data(17))
                Text(unit).font(.caption2).foregroundStyle(Theme.mute)
            }
            Text(note ?? " ").font(.data(9, weight: .regular)).foregroundStyle(Theme.mute)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}

struct WeightTrendChart: View {
    var points: [(date: Date, kg: Double)]

    var body: some View {
        Chart {
            ForEach(points.indices, id: \.self) { i in
                AreaMark(x: .value("Day", points[i].date), y: .value("kg", points[i].kg))
                    .foregroundStyle(LinearGradient(colors: [Theme.ice.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Day", points[i].date), y: .value("kg", points[i].kg))
                    .foregroundStyle(Theme.ice)
                    .interpolationMethod(.catmullRom)
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.date), y: .value("kg", last.kg)).foregroundStyle(Theme.ice)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 110)
    }
}
