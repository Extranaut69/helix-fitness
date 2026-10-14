import Foundation

// Value types shared by the iPhone and Watch apps. Kept free of SwiftData/HealthKit so the
// engines can be unit-tested and reused on both platforms.

enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

enum Goal: String, Codable, CaseIterable, Identifiable, Sendable {
    case recomp, fatLoss, muscleGain, endurance, maintain
    var id: String { rawValue }

    var title: String {
        switch self {
        case .recomp: "Recomposition"
        case .fatLoss: "Fat loss"
        case .muscleGain: "Muscle gain"
        case .endurance: "Endurance"
        case .maintain: "Maintain"
        }
    }

    /// Protein target in grams per kg of body mass.
    var proteinPerKg: Double {
        switch self {
        case .fatLoss: 2.2
        case .recomp: 2.0
        case .muscleGain: 1.8
        case .endurance, .maintain: 1.6
        }
    }

    /// Fractional change applied to measured daily energy expenditure.
    var calorieAdjustment: Double {
        switch self {
        case .fatLoss: -0.20
        case .muscleGain: 0.10
        case .recomp, .endurance, .maintain: 0
        }
    }
}

enum Diet: String, Codable, CaseIterable, Identifiable, Sendable {
    case omnivore, vegetarian, vegan
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    func allows(_ food: FoodInfo) -> Bool {
        switch self {
        case .omnivore: true
        case .vegetarian: food.diet != .omnivore
        case .vegan: food.diet == .vegan
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case low, moderate, high
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low: "Mostly sitting"
        case .moderate: "On my feet some"
        case .high: "Very active job"
        }
    }
    /// Daily active energy as a fraction of BMR, used only when no Apple Watch data exists.
    var estimatedActiveFraction: Double {
        switch self {
        case .low: 0.20
        case .moderate: 0.30
        case .high: 0.45
        }
    }
}

struct Macros: Codable, Hashable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = Macros()

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }
    static func - (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal - b.kcal, protein: a.protein - b.protein, carbs: a.carbs - b.carbs, fat: a.fat - b.fat)
    }
    func scaled(by f: Double) -> Macros {
        Macros(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f)
    }
}

/// Everything the engines need to know about a person.
struct ProfileSpec: Codable, Hashable, Sendable {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var goal: Goal
    var diet: Diet
    var activity: ActivityLevel
    var trainDaysPerWeek: Int
}

/// Nutrition per 100 g. Values come from USDA FoodData Central (public domain) or Open Food Facts (ODbL).
struct FoodInfo: Codable, Hashable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case protein, carb, veg, fat, mixed }
    enum DietClass: String, Codable, Sendable { case omnivore, vegetarian, vegan }

    var id: String
    var name: String
    var per100g: Macros
    /// g/cm³ — converts a LiDAR volume to grams.
    var density: Double
    /// Typical portion in grams, used when no depth data is available.
    var serving: Double
    var role: Role
    var diet: DietClass
    /// Labels from image classifiers that should map to this food.
    var aliases: [String] = []

    func macros(grams: Double) -> Macros { per100g.scaled(by: grams / 100) }
}
