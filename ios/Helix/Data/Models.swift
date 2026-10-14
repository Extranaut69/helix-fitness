import Foundation
import SwiftData

// Every stored property has a default and every relationship is optional, so the store can
// later be synced through the user's own iCloud (CloudKit) without a migration.

@Model
final class UserProfile {
    var id: UUID = UUID()
    var name: String = ""
    var sexRaw: String = Sex.male.rawValue
    var age: Int = 30
    var heightCm: Double = 170
    var weightKg: Double = 70
    var goalRaw: String = Goal.maintain.rawValue
    var dietRaw: String = Diet.omnivore.rawValue
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var trainDaysPerWeek: Int = 3
    /// Only the iPhone's owner can be linked to HealthKit; other people on the same
    /// device get estimated energy instead.
    var usesHealthKit: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \MealLog.profile) var meals: [MealLog]? = []
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.profile) var sets: [LoggedSet]? = []

    init(name: String, spec: ProfileSpec, usesHealthKit: Bool) {
        self.name = name
        self.usesHealthKit = usesHealthKit
        self.spec = spec
    }

    var spec: ProfileSpec {
        get {
            ProfileSpec(
                sex: Sex(rawValue: sexRaw) ?? .male, age: age, heightCm: heightCm, weightKg: weightKg,
                goal: Goal(rawValue: goalRaw) ?? .maintain, diet: Diet(rawValue: dietRaw) ?? .omnivore,
                activity: ActivityLevel(rawValue: activityRaw) ?? .moderate, trainDaysPerWeek: trainDaysPerWeek)
        }
        set {
            sexRaw = newValue.sex.rawValue; age = newValue.age; heightCm = newValue.heightCm
            weightKg = newValue.weightKg; goalRaw = newValue.goal.rawValue; dietRaw = newValue.diet.rawValue
            activityRaw = newValue.activity.rawValue; trainDaysPerWeek = newValue.trainDaysPerWeek
        }
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    func meals(on day: Date, calendar: Calendar = .current) -> [MealLog] {
        (meals ?? []).filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    func eaten(on day: Date) -> Macros {
        meals(on: day).reduce(.zero) { $0 + $1.total }
    }
}

@Model
final class MealLog {
    enum Source: String, Codable { case lidar, photo, barcode, manual, plan }

    var id: UUID = UUID()
    var date: Date = Date.now
    var name: String = ""
    var sourceRaw: String = Source.manual.rawValue
    var profile: UserProfile?
    @Relationship(deleteRule: .cascade, inverse: \LoggedFood.meal) var foods: [LoggedFood]? = []

    init(name: String, source: Source, date: Date = .now) {
        self.name = name
        self.sourceRaw = source.rawValue
        self.date = date
    }

    var source: Source { Source(rawValue: sourceRaw) ?? .manual }
    var total: Macros { (foods ?? []).reduce(.zero) { $0 + $1.macros } }
}

@Model
final class LoggedFood {
    var name: String = ""
    var grams: Double = 0
    var kcal100: Double = 0
    var protein100: Double = 0
    var carbs100: Double = 0
    var fat100: Double = 0
    /// Volume measured by LiDAR, kept so the estimate can be audited later.
    var measuredVolumeCm3: Double?
    var meal: MealLog?

    init(food: FoodInfo, grams: Double, volumeCm3: Double? = nil) {
        name = food.name
        self.grams = grams
        kcal100 = food.per100g.kcal
        protein100 = food.per100g.protein
        carbs100 = food.per100g.carbs
        fat100 = food.per100g.fat
        measuredVolumeCm3 = volumeCm3
    }

    var macros: Macros {
        Macros(kcal: kcal100, protein: protein100, carbs: carbs100, fat: fat100).scaled(by: grams / 100)
    }
}

@Model
final class LoggedSet {
    var date: Date = Date.now
    var exercise: String = ""
    var setIndex: Int = 0
    var reps: Int?
    var weightKg: Double?
    var profile: UserProfile?

    init(exercise: String, setIndex: Int, reps: Int?, weightKg: Double?, date: Date = .now) {
        self.exercise = exercise
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.date = date
    }
}
