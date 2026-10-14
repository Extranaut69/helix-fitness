import SwiftUI
import HealthKit

/// Heart-rate zones as one hue getting stronger, instead of a rainbow.
private let zoneColors: [Color] = [0.3, 0.45, 0.6, 0.8, 1.0].map { Palette.actionOnDark.opacity($0) }

struct WatchHomeView: View {
    @Environment(WatchLink.self) private var link
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.isRunning {
            LiveWorkoutView()
        } else if let day = link.day {
            // Same idea as the iPhone's Today screen: the face takes the colour of readiness.
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(day.readiness)")
                        .font(.score(78))
                        .tracking(-2)
                        .lineLimit(1)
                        .accessibilityLabel("Readiness \(day.readiness), \(day.readinessBand)")
                    Text(day.readinessBand).font(.display(18, weight: .heavy))
                    Text("\(Int(day.proteinLeft)) g protein and \(Int(day.kcalLeft)) kcal left")
                        .font(.system(size: 13))
                        .padding(.top, 2)
                    Rectangle().fill(Palette.onFlood.opacity(0.25)).frame(height: 1).padding(.vertical, 6)
                    Text(day.session.title).font(.display(16, weight: .semibold))
                    Button("Start strength") { Task { await workout.start(activity: .traditionalStrengthTraining) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.onFlood)
                        .foregroundStyle(Palette.flood(forScore: day.readiness))
                        .padding(.top, 4)
                    Button("Start run") { Task { await workout.start(activity: .running) } }
                        .buttonStyle(.bordered)
                        .tint(Palette.onFlood)
                }
                .foregroundStyle(Palette.onFlood)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .containerBackground(Palette.flood(forScore: day.readiness), for: .navigation)
        } else {
            VStack(spacing: 10) {
                Text("Open Helix on your iPhone once to sync today's plan.").multilineTextAlignment(.center).font(.footnote)
                Button("Start workout") { Task { await workout.start(activity: .traditionalStrengthTraining) } }
            }
            .navigationTitle("Helix")
        }
    }
}

struct LiveWorkoutView: View {
    @Environment(WatchLink.self) private var link
    @Environment(WorkoutManager.self) private var workout
    @State private var done: Set<String> = []

    var body: some View {
        TabView {
            // Page 1: live metrics
            VStack(alignment: .leading, spacing: 4) {
                if let start = workout.startDate {
                    Text(start, style: .timer).font(.display(24, weight: .semibold).monospacedDigit())
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(workout.heartRate))").font(.score(52).monospacedDigit())
                    Text("bpm").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Text("Zone \(workout.zone(for: workout.heartRate) + 1)").font(.display(15, weight: .bold))
                        .foregroundStyle(zoneColors[workout.zone(for: workout.heartRate)])
                }
                HStack(spacing: 3) {
                    let total = max(1, workout.zoneSeconds.reduce(0, +))
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(zoneColors[i]).frame(height: 6)
                            .frame(maxWidth: .infinity).scaleEffect(x: max(0.08, workout.zoneSeconds[i] / total), anchor: .leading)
                    }
                }
                Text("\(Int(workout.activeKcal)) active kcal").font(.footnote).foregroundStyle(.secondary)
                Button("End workout", role: .destructive) { Task { await workout.end() } }.padding(.top, 6)
            }

            // Page 2: tap sets as you finish them
            List {
                ForEach(link.day?.session.exercises ?? []) { ex in
                    Section(ex.name) {
                        ForEach(0..<ex.sets, id: \.self) { i in
                            let key = "\(ex.name)#\(i)"
                            Button {
                                guard !done.contains(key) else { return }
                                done.insert(key)
                                link.logSet(exercise: ex.name, index: i, reps: Int(ex.target.split(separator: " ").first ?? ""), weightKg: ex.weightKg)
                            } label: {
                                HStack {
                                    Text("Set \(i + 1)")
                                    Spacer()
                                    if let w = ex.weightKg { Text("\(w, specifier: "%.1f") kg").foregroundStyle(.secondary) }
                                    Image(systemName: done.contains(key) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(done.contains(key) ? Palette.actionOnDark : .secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .tabViewStyle(.verticalPage)
    }
}
