import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    let profile: UserProfile

    var body: some View {
        let session = model.session(for: profile)
        let readiness = model.readiness(for: profile)
        let todaySets = (profile.sets ?? []).filter { Calendar.current.isDateInToday($0.date) }
        let totalSets = session.exercises.reduce(0) { $0 + $1.sets }

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Readiness \(readiness.score)" + (readiness.loadRatio.map { String(format: " · load ratio %.2f", $0) } ?? ""))
                                    .font(.caption).foregroundStyle(Theme.mute)
                                Text("\(session.intensity) intensity").font(.headline)
                            }
                            Spacer()
                            Text("\(todaySets.count)/\(totalSets)").font(.data(22)) + Text(" sets").font(.caption).foregroundColor(Theme.mute)
                        }
                    }
                    Card {
                        ForEach(session.exercises) { ex in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(ex.name).font(.subheadline.weight(.semibold))
                                Text("\(ex.sets) × \(ex.target)" + (ex.weightKg.map { String(format: " @ %.1f kg", $0) } ?? ""))
                                    .font(.data(12)).foregroundStyle(Theme.mute)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 6) {
                                    ForEach(0..<ex.sets, id: \.self) { i in
                                        let done = todaySets.contains { $0.exercise == ex.name && $0.setIndex == i }
                                        Button { toggle(ex, i, done: done) } label: {
                                            Text(done ? "✓ Set \(i + 1)" : "Set \(i + 1)").font(.data(12))
                                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                                .background(done ? Theme.good.opacity(0.12) : Theme.hull, in: RoundedRectangle(cornerRadius: 11))
                                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(done ? Theme.good : Theme.line))
                                                .foregroundStyle(done ? Theme.good : .primary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    Text("Start the workout on Apple Watch to record heart rate. Sets you log there show up here.")
                        .font(.caption).foregroundStyle(Theme.mute)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle(session.title)
        }
    }

    private func toggle(_ ex: PlannedSession.Exercise, _ i: Int, done: Bool) {
        if done {
            (profile.sets ?? []).filter { Calendar.current.isDateInToday($0.date) && $0.exercise == ex.name && $0.setIndex == i }
                .forEach { context.delete($0) }
        } else {
            let reps = Int(ex.target.split(separator: " ").first ?? "")
            let set = LoggedSet(exercise: ex.name, setIndex: i, reps: reps, weightKg: ex.weightKg)
            set.profile = profile
            context.insert(set)
        }
        try? context.save()
    }
}
