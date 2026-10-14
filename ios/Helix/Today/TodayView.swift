import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile
    @Binding var showProfiles: Bool
    var openScan: () -> Void
    var openTrain: () -> Void
    var openPlan: () -> Void

    var body: some View {
        let readiness = model.readiness(for: profile)
        let targets = model.targets(for: profile)
        let session = model.session(for: profile)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionGap) {
                    ReadinessField(readiness: readiness, signals: signals(),
                                   headline: targets.isTrainingDay ? readiness.band.headline : "Rest day.",
                                   detail: detail(readiness, training: targets.isTrainingDay)) {
                        AvatarButton(initials: profile.initials) { showProfiles = true }
                    }
                    nextUp(session, training: targets.isTrainingDay)
                        .padding(.top, -12)
                    food(targets)
                    meals
                    weight
                    if !profile.usesHealthKit {
                        SourceNote("No Apple Watch is linked to this person, so energy is estimated from their profile.")
                            .padding(.horizontal, Theme.gutter)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Theme.fog)
            .refreshable { await model.refresh(profile) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Readiness

    private func hrvChange() -> Int? {
        let rec = model.recovery(for: profile)
        guard let v = rec.hrvMs, let b = rec.hrvBaselineMs, b > 0 else { return nil }
        return Int(((v - b) / b * 100).rounded())
    }

    /// The three signals behind the score, in everyday words.
    private func signals() -> [ReadinessSignal] {
        let rec = model.recovery(for: profile)
        let sleep: String = rec.sleepHours.map { $0 >= 7 ? "Good" : $0 >= 6 ? "A bit short" : "Too short" } ?? "No data"
        let recovery: String = hrvChange().map { $0 >= 3 ? "Strong" : $0 <= -8 ? "Low" : "Normal" } ?? "No data"
        var heart = "No data"
        if let v = rec.restingHR { heart = (rec.restingHRBaseline.map { v - $0 >= 4 } ?? false) ? "Raised" : "Normal" }
        return [
            .init(label: "Sleep", value: rec.sleepHours.map { String(format: "%.1f h", $0) } ?? "–", status: sleep),
            .init(label: "Recovery", value: recovery, status: rec.hrvMs.map { "HRV \(Int($0)) ms" } ?? "No HRV yet"),
            .init(label: "Resting heart", value: rec.restingHR.map { "\(Int($0)) bpm" } ?? "–", status: heart),
        ]
    }

    private func detail(_ r: Readiness, training: Bool) -> String {
        guard profile.usesHealthKit else {
            return "Without Apple Watch data, readiness uses neutral values."
        }
        let rec = model.recovery(for: profile)
        var sentence = ""
        if let h = rec.sleepHours {
            sentence = String(format: h >= 7 ? "You slept %.1f hours" : "You only slept %.1f hours", h)
        }
        if let d = hrvChange() {
            let body = d >= 3 ? "your body has recovered well" : d <= -8 ? "your body is still recovering" : "your recovery is normal"
            sentence = sentence.isEmpty ? String(body.prefix(1)).uppercased() + String(body.dropFirst()) : sentence + " and " + body
        }
        if !sentence.isEmpty { sentence += "." }
        guard !training else { return sentence }
        let tip = switch r.band {
        case .primed: "You are fully recovered for tomorrow."
        case .steady: "An easy walk is plenty today."
        case .recover: "Keep today easy and get to bed early."
        }
        return sentence.isEmpty ? tip : sentence + " " + tip
    }

    // MARK: Next up

    private func nextUp(_ session: PlannedSession, training: Bool) -> some View {
        let sets = session.exercises.reduce(0) { $0 + $1.sets }
        let minutes = Int((Double(sets * 3 + 10) / 5).rounded()) * 5
        return Panel {
            VStack(alignment: .leading, spacing: 2) {
                Text(training ? "Today's workout" : "Rest day").font(.system(size: 14)).foregroundStyle(Theme.ink2)
                Text(training ? session.title : "Easy walk and stretching")
                    .font(.system(size: 21, weight: .semibold).width(.condensed)).foregroundStyle(Theme.ink)
            }
            Text(training
                 ? "\(session.exercises.count) exercises, about \(minutes) minutes. \(session.intensity) effort, set by your readiness."
                 : "Thirty minutes of walking and some light mobility is all you need today.")
                .font(.system(size: 15)).foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button(training ? "Start workout" : "See what to do", action: openTrain)
                .buttonStyle(.helix(.primary, fill: true))
                .padding(.top, 4)
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Food

    private func food(_ targets: DailyTargets) -> some View {
        let eaten = profile.eaten(on: .now)
        let left = targets.macros.kcal - eaten.kcal
        let parts = [
            MacroPart(name: "Protein", eaten: eaten.protein, target: targets.macros.protein, color: Theme.protein),
            MacroPart(name: "Carbs", eaten: eaten.carbs, target: targets.macros.carbs, color: Theme.carbs),
            MacroPart(name: "Fat", eaten: eaten.fat, target: targets.macros.fat, color: Theme.fat),
        ]
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Food") {
                Button("Scan a meal", action: openScan).buttonStyle(.helix(.primary, small: true))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Int(abs(left).rounded()), format: .number).font(.display(42, weight: .heavy).monospacedDigit())
                    Text(left >= 0 ? "kcal left to eat" : "kcal over your target").font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Theme.ink)
                .accessibilityElement(children: .combine)
                Text("You've eaten \(Int(eaten.kcal)) of \(Int(targets.macros.kcal)) kcal today.")
                    .font(.system(size: 14)).foregroundStyle(Theme.ink2)
            }
            MacroBars(parts: parts)
        }
        .padding(.horizontal, Theme.gutter)
    }

    // MARK: Meals

    private var meals: some View {
        let logged = profile.meals(on: .now)
        let rem = model.remaining(for: profile)
        let loggedNames = Set(logged.map(\.name))
        let next = MealPlanner.restOfDay(remaining: Macros(kcal: max(0, rem.kcal), protein: max(0, rem.protein),
                                                           carbs: max(0, rem.carbs), fat: max(0, rem.fat)),
                                         diet: profile.spec.diet)
            .first { !loggedNames.contains($0.name) }
        let count = logged.count + (next == nil ? 0 : 1)

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Meals today")
            if logged.isEmpty {
                Text("Nothing logged yet. Tap Scan a meal to add your first one.").font(.system(size: 15)).foregroundStyle(Theme.ink2)
            }
            VStack(spacing: 0) {
                ForEach(Array(logged.enumerated()), id: \.element.id) { i, meal in
                    TimelineRow(time: meal.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()),
                                isFirst: i == 0, isLast: i == count - 1) {
                        Text(meal.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                        Text(foodList((meal.foods ?? []).map(\.name))).font(.system(size: 14)).foregroundStyle(Theme.ink2)
                    } trailing: {
                        kcal(meal.total.kcal, planned: false)
                    }
                }
                if let next {
                    TimelineRow(time: next.time, planned: true, isFirst: logged.isEmpty, isLast: true) {
                        Text("Up next: \(next.name.lowercased())").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink2)
                        Text("Suggested: " + foodList(next.items.map { $0.food.name }).lowercased())
                            .font(.system(size: 14)).foregroundStyle(Theme.ink2)
                    } trailing: {
                        kcal(next.macros.kcal, planned: true)
                    }
                }
            }
            Button("See the rest of today's plan", action: openPlan)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.action)
        }
        .padding(.horizontal, Theme.gutter)
    }

    private func kcal(_ value: Double, planned: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(Int(value), format: .number).font(.figure(14))
                .foregroundStyle(planned ? Theme.ink2 : Theme.ink)
            Text("kcal").font(.system(size: 12)).foregroundStyle(Theme.ink2)
        }
    }

    /// "Rolled oats, banana, almonds": one sentence-case line.
    private func foodList(_ names: [String]) -> String {
        names.enumerated().map { i, n -> String in i == 0 ? n : String(n.prefix(1)).lowercased() + String(n.dropFirst()) }.joined(separator: ", ")
    }

    // MARK: Weight

    @ViewBuilder private var weight: some View {
        if let points = model.snapshot?.bodyMass, profile.usesHealthKit, points.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weight") {
                    if let w = model.snapshot?.weeklyWeightChange {
                        Text(abs(w) < 0.02 ? "Steady" : String(format: "%@ %.2f kg a week", w < 0 ? "Down" : "Up", abs(w)))
                            .font(.system(size: 14)).foregroundStyle(Theme.ink2)
                    }
                }
                WeightTrendChart(points: points)
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

extension MealLog.Source {
    /// How the meal was logged, in the words a person would use.
    var label: String {
        switch self {
        case .lidar: "Measured with LiDAR"
        case .photo: "Recognised from a photo"
        case .barcode: "Barcode, Open Food Facts"
        case .manual: "Logged by hand"
        case .plan: "From your plan"
        }
    }
}
