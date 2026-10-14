import Foundation

/// Measured (or estimated) energy for one day.
struct EnergySnapshot: Codable, Sendable {
    var restingKcal: Double
    var activeKcalToday: Double
    /// Planning uses the 7-day average so targets don't swing with the time of day.
    var activeKcal7DayAvg: Double
    var isMeasured: Bool
}

struct DailyTargets: Codable, Sendable {
    var macros: Macros
    var tdee: Double
    var isTrainingDay: Bool
}

enum NutritionEngine {
    /// Mifflin–St Jeor.
    static func bmr(_ p: ProfileSpec) -> Double {
        10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age) + (p.sex == .male ? 5 : -161)
    }

    /// Fallback for profiles without an Apple Watch (e.g. a family member sharing an iPad).
    static func estimatedEnergy(for p: ProfileSpec) -> EnergySnapshot {
        let rest = bmr(p)
        let active = rest * (p.activity.estimatedActiveFraction + Double(p.trainDaysPerWeek) * 0.015)
        return EnergySnapshot(restingKcal: rest, activeKcalToday: active * 0.6, activeKcal7DayAvg: active, isMeasured: false)
    }

    /// Calendar weekdays (1 = Sunday) used for training, spread across the week.
    static func trainingWeekdays(count: Int) -> Set<Int> {
        switch count {
        case ...0: []
        case 1: [2]
        case 2: [2, 5]
        case 3: [2, 4, 6]
        case 4: [2, 3, 5, 6]
        case 5: [2, 3, 4, 6, 7]
        case 6: [2, 3, 4, 5, 6, 7]
        default: Set(1...7)
        }
    }

    static func isTrainingDay(_ p: ProfileSpec, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        trainingWeekdays(count: p.trainDaysPerWeek).contains(calendar.component(.weekday, from: date))
    }

    /// - Parameter adaptiveKcal: correction from `adaptiveAdjustment`, learned from the weight trend.
    static func targets(for p: ProfileSpec, energy: EnergySnapshot, adaptiveKcal: Double = 0, date: Date = .now) -> DailyTargets {
        let training = isTrainingDay(p, on: date)
        let tdee = energy.restingKcal + energy.activeKcal7DayAvg

        var kcal: Double
        switch p.goal {
        case .recomp:
            // Small surplus on lifting days, deficit on rest days: roughly maintenance across the week.
            kcal = tdee * (training ? 1.05 : 0.88)
        default:
            kcal = tdee * (1 + p.goal.calorieAdjustment)
        }
        kcal = ((kcal + adaptiveKcal) / 10).rounded() * 10

        let protein = (p.goal.proteinPerKg * p.weightKg).rounded()
        var carbs: Double
        var fat: Double

        if p.goal == .endurance {
            // Carb periodisation: fuel the work required.
            carbs = (p.weightKg * (training ? 6 : 3.5)).rounded()
            fat = max(0.8 * p.weightKg, (kcal - protein * 4 - carbs * 4) / 9).rounded()
            kcal = protein * 4 + carbs * 4 + fat * 9
        } else {
            fat = max(0.8 * p.weightKg, kcal * 0.27 / 9).rounded()
            carbs = max(50, ((kcal - protein * 4 - fat * 9) / 4).rounded())
        }

        return DailyTargets(macros: Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat), tdee: tdee, isTrainingDay: training)
    }

    /// Compares the real weekly weight change with the goal's expected rate and returns a
    /// calorie correction (±150 kcal per step), so targets self-correct when the
    /// watch over- or under-estimates burn.
    static func adaptiveAdjustment(goal: Goal, weeklyChangeKg: Double?, weightKg: Double) -> Double {
        guard let weekly = weeklyChangeKg else { return 0 }
        let pct = weekly / weightKg * 100
        switch goal {
        case .fatLoss:
            if pct > -0.3 { return -150 }      // losing too slowly
            if pct < -1.0 { return 150 }       // losing too fast, protect muscle
        case .muscleGain:
            if pct < 0.1 { return 150 }
            if pct > 0.5 { return -150 }
        case .recomp, .maintain, .endurance:
            if pct < -0.5 { return 150 }
            if pct > 0.5 { return -150 }
        }
        return 0
    }
}
