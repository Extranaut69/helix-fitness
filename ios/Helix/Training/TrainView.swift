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
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: session.title, subtitle: "\(session.intensity) intensity, set by readiness \(readiness.score).")

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 3).fill(Theme.flood(for: readiness.band)).frame(width: 12, height: 12)
                                Text(readiness.band.title).font(.system(size: 14, weight: .semibold))
                            }
                            Spacer()
                            Text("\(todaySets.count) of \(totalSets) sets").font(.figure(13, weight: .regular)).foregroundStyle(Theme.ink2)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.wash)
                                Capsule().fill(Theme.ink)
                                    .frame(width: geo.size.width * CGFloat(totalSets == 0 ? 0 : Double(todaySets.count) / Double(totalSets)))
                            }
                        }
                        .frame(height: 6)
                        .animation(.easeOut(duration: 0.25), value: todaySets.count)
                        Text("Tap a numbered box when you finish that set.")
                            .font(.system(size: 14)).foregroundStyle(Theme.ink2)
                    }
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.gutter)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.exercises.enumerated()), id: \.element.id) { n, ex in
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                                    Text("\(ex.sets) × \(ex.target)" + (ex.weightKg.map { String(format: " at %.1f kg", $0) } ?? ""))
                                        .font(.figure(13.5, weight: .regular)).foregroundStyle(Theme.ink2)
                                }
                                HStack(spacing: 8) {
                                    ForEach(0..<ex.sets, id: \.self) { i in
                                        let done = todaySets.contains { $0.exercise == ex.name && $0.setIndex == i }
                                        Button { toggle(ex, i, done: done) } label: {
                                            Text("\(i + 1)").font(.figure(15))
                                                .frame(width: 44, height: 44)
                                                .foregroundStyle(done ? Theme.fog : Theme.ink)
                                                .background(done ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(done ? Theme.ink : Theme.rule, lineWidth: 1.5))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(ex.name) set \(i + 1)")
                                        .accessibilityAddTraits(done ? .isSelected : [])
                                    }
                                }
                            }
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(alignment: .top) { if n > 0 { Rectangle().fill(Theme.rule).frame(height: 1) } }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, 18)

                    SourceNote("Start the workout on Apple Watch to record heart rate. Sets you log there show up here.")
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, 12)
                }
                .padding(.bottom, 32)
            }
            .background(Theme.fog)
            .toolbar(.hidden, for: .navigationBar)
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
