import Foundation

/// Picks today's session from goal + readiness, and applies progressive overload from history.
enum WorkoutPlanner {
    @MainActor
    static func plan(for p: UserProfile, readiness: Readiness, isTrainingDay: Bool) -> PlannedSession {
        let r = readiness.score
        guard isTrainingDay else {
            return PlannedSession(title: "Rest day · mobility", intensity: "Easy", exercises: [
                .init(name: "Zone 2 walk", sets: 1, target: "30 min"),
                .init(name: "Hip & thoracic mobility", sets: 2, target: "8 min"),
            ])
        }

        if p.spec.goal == .endurance {
            if r >= 75 {
                return PlannedSession(title: "Threshold intervals", intensity: "Hard", exercises: [
                    .init(name: "Warm-up Z2", sets: 1, target: "15 min"),
                    .init(name: "Z4 intervals", sets: 5, target: "4 min on / 2 min easy"),
                    .init(name: "Cool-down", sets: 1, target: "10 min"),
                ])
            }
            return PlannedSession(title: "Aerobic base", intensity: r >= 55 ? "Moderate" : "Easy", exercises: [
                .init(name: "Z2 run", sets: 1, target: r >= 55 ? "50 min" : "30 min"),
            ] + (r >= 55 ? [.init(name: "Strides", sets: 4, target: "20 s")] : []))
        }

        // Strength: rotate lower/upper by day-of-year so consecutive sessions differ.
        let lowerDay = Calendar.current.ordinality(of: .day, in: .year, for: .now)! % 2 == 0
        let scale = r >= 75 ? 1.0 : r >= 55 ? 0.9 : 0.75
        let template: [(String, Int, String, Double?)] = lowerDay
            ? [("Back squat", 4, "5 reps", 1.25), ("Romanian deadlift", 3, "8 reps", 1.1), ("Walking lunge", 3, "10 reps", 0.35), ("Plank", 3, "45 s", nil)]
            : [("Bench press", 4, "6 reps", 0.95), ("Pull-up / lat pulldown", 4, "8 reps", 0.7), ("Overhead press", 3, "8 reps", 0.55), ("Cable row", 3, "10 reps", 0.7)]
        let sexFactor = p.spec.sex == .male ? 1.0 : 0.62

        let exercises = template.map { name, sets, target, bwRatio -> PlannedSession.Exercise in
            let start = bwRatio.map { $0 * p.weightKg * sexFactor * 0.6 }    // conservative first estimate
            let weight = progressed(name: name, target: target, history: p.sets ?? [], fallback: start).map { roundPlate($0 * scale) }
            return .init(name: name, sets: r < 55 ? max(2, sets - 1) : sets, target: target, weightKg: weight)
        }
        return PlannedSession(title: lowerDay ? "Lower body" : "Upper body",
                              intensity: r >= 75 ? "Hard" : r >= 55 ? "Moderate" : "Easy (technique)",
                              exercises: exercises)
    }

    /// Double progression: if every set last session hit the target reps, add 2.5 kg.
    private static func progressed(name: String, target: String, history: [LoggedSet], fallback: Double?) -> Double? {
        let past = history.filter { $0.exercise == name && !Calendar.current.isDateInToday($0.date) }
        guard let lastDay = past.map(\.date).max() else { return fallback }
        let session = past.filter { Calendar.current.isDate($0.date, inSameDayAs: lastDay) }
        guard let top = session.compactMap(\.weightKg).max() else { return fallback }
        let targetReps = Int(target.split(separator: " ").first ?? "") ?? 0
        let hitAll = session.allSatisfy { ($0.reps ?? 0) >= targetReps }
        return hitAll ? top + 2.5 : top
    }

    private static func roundPlate(_ kg: Double) -> Double { (kg / 2.5).rounded() * 2.5 }
}
