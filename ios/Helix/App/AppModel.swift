import Foundation
import SwiftData
import Observation

/// App-wide state: who is active, their HealthKit snapshot, and the derived targets.
@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let health = HealthKitManager.shared
    let food = FoodDatabase.shared
    let connectivity: PhoneConnectivity

    var activeProfileID: UUID? {
        didSet { UserDefaults.standard.set(activeProfileID?.uuidString, forKey: "activeProfileID") }
    }
    private(set) var snapshot: HealthKitManager.DaySnapshot?
    private(set) var isRefreshing = false

    init(container: ModelContainer) {
        self.container = container
        self.connectivity = PhoneConnectivity(container: container)
        if let s = UserDefaults.standard.string(forKey: "activeProfileID") { activeProfileID = UUID(uuidString: s) }
    }

    var context: ModelContext { container.mainContext }

    func activeProfile(in profiles: [UserProfile]) -> UserProfile? {
        profiles.first { $0.id == activeProfileID } ?? profiles.first
    }

    // MARK: - Derived values for a profile

    func energy(for p: UserProfile) -> EnergySnapshot {
        if p.usesHealthKit, let s = snapshot { return s.energy }
        return NutritionEngine.estimatedEnergy(for: p.spec)
    }

    func recovery(for p: UserProfile) -> RecoverySignals {
        if p.usesHealthKit, let s = snapshot { return s.recovery }
        return RecoverySignals()
    }

    func readiness(for p: UserProfile) -> Readiness { ReadinessEngine.evaluate(recovery(for: p)) }

    func targets(for p: UserProfile) -> DailyTargets {
        let adaptive = p.usesHealthKit
            ? NutritionEngine.adaptiveAdjustment(goal: p.spec.goal, weeklyChangeKg: snapshot?.weeklyWeightChange, weightKg: p.weightKg)
            : 0
        return NutritionEngine.targets(for: p.spec, energy: energy(for: p), adaptiveKcal: adaptive)
    }

    func remaining(for p: UserProfile) -> Macros { targets(for: p).macros - p.eaten(on: .now) }

    func session(for p: UserProfile) -> PlannedSession {
        WorkoutPlanner.plan(for: p, readiness: readiness(for: p), isTrainingDay: targets(for: p).isTrainingDay)
    }

    // MARK: - Actions

    func refresh(_ p: UserProfile) async {
        guard p.usesHealthKit, health.isAvailable else { pushToWatch(p); return }
        isRefreshing = true
        defer { isRefreshing = false }
        try? await health.requestAuthorization()
        snapshot = await health.snapshot(for: p.spec)
        // Keep the profile's weight current from the latest weigh-in.
        if let latest = snapshot?.bodyMass.last?.kg { p.weightKg = (latest * 10).rounded() / 10 }
        pushToWatch(p)
    }

    func log(_ items: [(FoodInfo, grams: Double, volume: Double?)], name: String, source: MealLog.Source, for p: UserProfile) {
        let meal = MealLog(name: name, source: source)
        meal.profile = p
        context.insert(meal)
        for (food, grams, volume) in items where grams > 0 {
            let f = LoggedFood(food: food, grams: grams, volumeCm3: volume)
            f.meal = meal
            context.insert(f)
        }
        try? context.save()
        if p.usesHealthKit { Task { await health.save(meal: meal.total, at: meal.date) } }
        pushToWatch(p)
    }

    func pushToWatch(_ p: UserProfile) {
        let r = readiness(for: p), rem = remaining(for: p)
        connectivity.send(WatchDayContext(
            profileName: p.name, readiness: r.score, readinessBand: r.band.title,
            proteinLeft: max(0, rem.protein), kcalLeft: max(0, rem.kcal),
            session: session(for: p), updatedAt: .now))
    }
}
