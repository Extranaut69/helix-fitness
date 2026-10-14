import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The AI coach. Uses Apple's on-device Foundation Models (iOS 26+, free, private) when the
/// phone supports Apple Intelligence, and a rule-based coach everywhere else. Both answer
/// from the same data snapshot, so advice is always grounded in the user's numbers.
@MainActor
final class CoachService {
    struct Context {
        var name: String
        var spec: ProfileSpec
        var targets: DailyTargets
        var eaten: Macros
        var readiness: Readiness
        var recovery: RecoverySignals
        var session: PlannedSession
        var weeklyWeightChange: Double?
        var nextMeal: [(food: FoodInfo, grams: Double)]

        var remaining: Macros { targets.macros - eaten }

        /// Plain-text facts handed to the language model.
        var facts: String {
            var lines = [
                "Person: \(name), \(spec.age) y, \(Int(spec.heightCm)) cm, \(String(format: "%.1f", spec.weightKg)) kg, goal \(spec.goal.title), diet \(spec.diet.label).",
                "Today's target: \(Int(targets.macros.kcal)) kcal, \(Int(targets.macros.protein)) g protein, \(Int(targets.macros.carbs)) g carbs, \(Int(targets.macros.fat)) g fat. \(targets.isTrainingDay ? "Training day." : "Rest day.")",
                "Eaten so far: \(Int(eaten.kcal)) kcal, \(Int(eaten.protein)) g protein, \(Int(eaten.carbs)) g carbs, \(Int(eaten.fat)) g fat.",
                "Readiness \(readiness.score)/100 (\(readiness.band.title)); weakest signal: \(readiness.weakest?.name ?? "none").",
                "Planned session: \(session.title), \(session.intensity) intensity.",
            ]
            if let h = recovery.hrvMs, let b = recovery.hrvBaselineMs { lines.append("HRV \(Int(h)) ms vs baseline \(Int(b)) ms.") }
            if let r = recovery.restingHR, let b = recovery.restingHRBaseline { lines.append("Resting HR \(Int(r)) bpm vs baseline \(Int(b)).") }
            if let s = recovery.sleepHours { lines.append(String(format: "Slept %.1f h.", s)) }
            if let w = weeklyWeightChange { lines.append(String(format: "Weight trend %+.2f kg per week.", w)) }
            return lines.joined(separator: "\n")
        }
    }

    enum Engine { case onDevice, rules }

    var engine: Engine {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return .onDevice }
        #endif
        return .rules
    }

    func reply(to question: String, context: Context) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), engine == .onDevice {
            let instructions = """
            You are Helix, a concise, evidence-based fitness and nutrition coach. Answer in 2–4 short sentences, \
            using the person's numbers below. Never invent data that isn't listed. Respect their diet. \
            You are not a doctor: for pain, illness, injury or eating-disorder concerns, suggest seeing a professional.

            \(context.facts)
            """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: question)
                return response.content
            } catch {
                // Guardrail refusals or context errors fall through to the rule-based coach.
            }
        }
        #endif
        return Self.ruleBased(question, context)
    }

    static func ruleBased(_ raw: String, _ c: Context) -> String {
        let q = raw.lowercased()
        let rem = c.remaining
        func has(_ words: String...) -> Bool { words.contains { q.contains($0) } }

        if has("eat", "dinner", "lunch", "snack", "hungry", "meal", "food") {
            let meal = c.nextMeal.map { "\(Int($0.grams)) g \($0.food.name.lowercased())" }.joined(separator: ", ")
            let m = c.nextMeal.reduce(Macros.zero) { $0 + $1.food.macros(grams: $1.grams) }
            return "You have \(Int(max(0, rem.kcal))) kcal left: \(Int(max(0, rem.protein))) g protein, \(Int(max(0, rem.carbs))) g carbs, \(Int(max(0, rem.fat))) g fat. Next meal: \(meal). That's about \(Int(m.kcal)) kcal and \(Int(m.protein)) g protein."
        }
        if has("recover", "ready", "readiness", "train", "workout", "gym", "tired", "sore") {
            let advice = c.readiness.score < 55 ? "Keep it easy and stop 3+ reps short of failure."
                : c.readiness.score < 75 ? "Train hard, but leave 2 reps in reserve on every set."
                : "You're fresh, so this is a good day to go for a top-set PR."
            return "Readiness is \(c.readiness.score). The weakest signal is \(c.readiness.weakest?.name.lowercased() ?? "none"). Today is \(c.session.title.lowercased()). \(advice)"
        }
        if has("protein") {
            return rem.protein > 0
                ? "You need \(Int(rem.protein)) g more protein today (target \(Int(c.targets.macros.protein)) g). Split it into meals of 30–45 g."
                : "You've already hit your \(Int(c.targets.macros.protein)) g protein target today."
        }
        if has("sleep") {
            guard let s = c.recovery.sleepHours else { return "No sleep data yet. Wear your Watch to bed with Sleep Focus on." }
            return s < 7
                ? String(format: "You slept %.1f h. Under 7 h lowers recovery and raises hunger, so aim for lights out 30 minutes earlier tonight.", s)
                : String(format: "You slept %.1f h, which is solid. Keep the same bedtime.", s)
        }
        if has("weight", "progress", "plateau", "scale", "stuck") {
            guard let w = c.weeklyWeightChange else { return "I need at least five weigh-ins in the last three weeks to read your trend." }
            return String(format: "Your weight is moving %+.2f kg per week. ", w) + (NutritionEngine.adaptiveAdjustment(goal: c.spec.goal, weeklyChangeKg: w, weightKg: c.spec.weightKg) == 0
                ? "That's on pace for your goal, so no change."
                : "That's off pace, so your calorie target has already been adjusted by 150 kcal.")
        }
        return "Today: readiness \(c.readiness.score), \(Int(c.targets.macros.kcal)) kcal with \(Int(c.targets.macros.protein)) g protein, and \(c.session.title.lowercased()). Ask what to eat, whether to train hard, or how your progress is going."
    }
}
