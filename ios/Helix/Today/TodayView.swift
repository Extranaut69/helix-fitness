import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile
    @Binding var showProfiles: Bool
    var openScan: () -> Void

    var body: some View {
        let readiness = model.readiness(for: profile)
        let targets = model.targets(for: profile)
        let energy = model.energy(for: profile)
        let eaten = profile.eaten(on: .now)
        let rec = model.recovery(for: profile)

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        HStack(spacing: 16) {
                            ReadinessRing(score: readiness.score)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(readiness.band.title) · \(model.session(for: profile).intensity.lowercased())")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .overlay(Capsule().stroke(Theme.color(for: readiness.band)))
                                    .foregroundStyle(Theme.color(for: readiness.band))
                                ForEach(readiness.components) { c in
                                    HStack(spacing: 8) {
                                        Text(c.name).font(.caption).foregroundStyle(Theme.mute).frame(width: 64, alignment: .leading)
                                        ProgressView(value: c.score, total: 100).tint(Theme.scoreColor(c.score))
                                        Text("\(Int(c.score))").font(.data(11)).foregroundStyle(Theme.mute).frame(width: 26, alignment: .trailing)
                                    }
                                }
                            }
                        }
                        if !profile.usesHealthKit {
                            Text("No Apple Watch linked to this person, so readiness uses neutral values.")
                                .font(.caption).foregroundStyle(Theme.mute)
                        }
                    }

                    HStack(spacing: 8) {
                        StatTile(label: "HRV", value: rec.hrvMs.map { "\(Int($0))" } ?? "–", unit: "ms",
                                 note: compare(rec.hrvMs, rec.hrvBaselineMs, higherIsBetter: true))
                        StatTile(label: "Rest HR", value: rec.restingHR.map { "\(Int($0))" } ?? "–", unit: "bpm",
                                 note: compare(rec.restingHR, rec.restingHRBaseline, higherIsBetter: false))
                        StatTile(label: "Sleep", value: rec.sleepHours.map { String(format: "%.1f", $0) } ?? "–", unit: "h")
                        StatTile(label: "VO₂", value: rec.vo2Max.map { String(format: "%.0f", $0) } ?? "–", unit: "")
                    }

                    Card {
                        HStack {
                            Eyebrow(energy.isMeasured ? "Energy · Apple Watch" : "Energy · estimated")
                            Spacer()
                            Text(targets.isTrainingDay ? "Training day" : "Rest day").font(.caption.weight(.semibold)).foregroundStyle(Theme.ice)
                        }
                        HStack(alignment: .bottom) {
                            metric("Eaten", eaten.kcal)
                            Spacer()
                            metric("Target", targets.macros.kcal, color: Theme.ice)
                            Spacer()
                            metric("Burned so far", energy.restingKcal * fractionOfDay() + energy.activeKcalToday)
                        }
                        ProgressView(value: min(eaten.kcal, targets.macros.kcal), total: max(targets.macros.kcal, 1)).tint(Theme.ice)
                        Text("Resting \(Int(energy.restingKcal)) + 7-day active avg \(Int(energy.activeKcal7DayAvg)) · \(profile.spec.goal.title.lowercased()) plan")
                            .font(.data(11, weight: .regular)).foregroundStyle(Theme.mute)
                    }

                    Card {
                        HStack {
                            Eyebrow("Macros")
                            Spacer()
                            Text("\(Int(max(0, targets.macros.kcal - eaten.kcal))) kcal left").font(.data(12)).foregroundStyle(Theme.mute)
                        }
                        MacroBar(label: "Protein", value: eaten.protein, target: targets.macros.protein, color: Theme.protein)
                        MacroBar(label: "Carbs", value: eaten.carbs, target: targets.macros.carbs, color: Theme.carbs)
                        MacroBar(label: "Fat", value: eaten.fat, target: targets.macros.fat, color: Theme.fat)
                    }

                    Card {
                        HStack {
                            Eyebrow("Meals")
                            Spacer()
                            Button("Scan meal", systemImage: "plus", action: openScan).font(.caption.weight(.semibold))
                        }
                        let meals = profile.meals(on: .now)
                        if meals.isEmpty {
                            Text("Nothing logged yet. Scan your first meal with the camera.").font(.subheadline).foregroundStyle(Theme.mute)
                        }
                        ForEach(meals) { meal in
                            MealRow(meal: meal)
                        }
                    }

                    if let points = model.snapshot?.bodyMass, profile.usesHealthKit, points.count > 1 {
                        Card {
                            HStack {
                                Eyebrow("Body mass · Health")
                                Spacer()
                                if let w = model.snapshot?.weeklyWeightChange {
                                    Text(String(format: "%+.2f kg / wk", w)).font(.data(12)).foregroundStyle(Theme.mute)
                                }
                            }
                            WeightTrendChart(points: points)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh(profile) }
            .navigationTitle(profile.name)
            .toolbar {
                Button { showProfiles = true } label: {
                    Text(profile.initials).font(.footnote.weight(.bold)).frame(width: 34, height: 34)
                        .background(Theme.panel, in: Circle()).overlay(Circle().stroke(Theme.line))
                }
                .accessibilityLabel("Switch person or edit profile")
            }
        }
    }

    private func metric(_ label: String, _ kcal: Double, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(Theme.mute)
            Text("\(Int(kcal))").font(.data(22)).foregroundStyle(color)
        }
    }

    private func fractionOfDay() -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        return Date.now.timeIntervalSince(start) / 86_400
    }

    private func compare(_ v: Double?, _ base: Double?, higherIsBetter: Bool) -> String? {
        guard let v, let base else { return nil }
        let up = v >= base
        return "\(up ? "▲" : "▼") vs base"
    }
}

struct MealRow: View {
    let meal: MealLog
    var body: some View {
        let t = meal.total
        HStack(alignment: .top, spacing: 10) {
            Text(meal.date, format: .dateTime.hour().minute()).font(.data(12)).foregroundStyle(Theme.mute).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).font(.subheadline.weight(.semibold))
                Text((meal.foods ?? []).map(\.name).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.mute)
                Text(meal.source.rawValue.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.ice)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(t.kcal)) kcal").font(.data(12))
                HStack(spacing: 4) {
                    Text("\(Int(t.protein))P").foregroundStyle(Theme.protein)
                    Text("\(Int(t.carbs))C").foregroundStyle(Theme.carbs)
                    Text("\(Int(t.fat))F").foregroundStyle(Theme.fat)
                }
                .font(.data(11))
            }
        }
        .padding(.vertical, 6)
    }
}
