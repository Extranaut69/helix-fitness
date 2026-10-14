import SwiftUI
import HealthKit

private let ice = Color(red: 0.498, green: 0.878, blue: 1.0)
private let zoneColors: [Color] = [.gray, .blue, .green, .yellow, .red]

struct WatchHomeView: View {
    @Environment(WatchLink.self) private var link
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        if workout.isRunning {
            LiveWorkoutView()
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    if let day = link.day {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                            Circle().trim(from: 0, to: CGFloat(day.readiness) / 100)
                                .stroke(ice, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                            VStack(spacing: 0) {
                                Text("\(day.readiness)").font(.system(size: 30, weight: .bold, design: .rounded))
                                Text(day.readinessBand.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 96, height: 96)
                        HStack {
                            Label("\(Int(day.proteinLeft)) g", systemImage: "fork.knife").foregroundStyle(.orange)
                            Spacer()
                            Text("\(Int(day.kcalLeft)) kcal").foregroundStyle(.secondary)
                        }
                        .font(.footnote)
                        Text(day.session.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Start strength") { Task { await workout.start(activity: .traditionalStrengthTraining) } }
                            .tint(ice)
                        Button("Start run") { Task { await workout.start(activity: .running) } }
                    } else {
                        Text("Open Helix on your iPhone once to sync today's plan.").multilineTextAlignment(.center).font(.footnote)
                        Button("Start workout") { Task { await workout.start(activity: .traditionalStrengthTraining) } }
                    }
                }
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
                    Text(start, style: .timer).font(.system(.title2, design: .rounded).monospacedDigit()).foregroundStyle(.yellow)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(workout.heartRate))").font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("BPM").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Z\(workout.zone(for: workout.heartRate) + 1)").font(.headline)
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
                                    Image(systemName: done.contains(key) ? "checkmark.circle.fill" : "circle").foregroundStyle(done.contains(key) ? .green : .secondary)
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
