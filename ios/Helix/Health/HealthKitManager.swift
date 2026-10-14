import Foundation
import HealthKit

/// Reads Apple Watch data from HealthKit and writes logged nutrition back to the Health app.
/// All queries use the async descriptor APIs (iOS 15.4+).
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.basalEnergyBurned),
        HKQuantityType(.stepCount),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRate),
        HKQuantityType(.vo2Max),
        HKQuantityType(.bodyMass),
        HKCategoryType(.sleepAnalysis),
        HKObjectType.workoutType(),
    ]

    private let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed),
        HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates),
        HKQuantityType(.dietaryFatTotal),
        HKQuantityType(.bodyMass),
    ]

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    // MARK: - Snapshot

    struct DaySnapshot: Sendable {
        var energy: EnergySnapshot
        var recovery: RecoverySignals
        var steps: Double
        var bodyMass: [(date: Date, kg: Double)]
        /// kg per week from a least-squares fit of the last 21 days, nil with < 5 weigh-ins.
        var weeklyWeightChange: Double?
    }

    func snapshot(for spec: ProfileSpec, now: Date = .now) async -> DaySnapshot {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let d7 = cal.date(byAdding: .day, value: -7, to: startOfDay)!
        let d28 = cal.date(byAdding: .day, value: -28, to: startOfDay)!
        let d21 = cal.date(byAdding: .day, value: -21, to: startOfDay)!

        async let activeToday = sum(.activeEnergyBurned, .kilocalorie(), from: startOfDay, to: now)
        async let active7 = sum(.activeEnergyBurned, .kilocalorie(), from: d7, to: startOfDay)
        async let resting7 = sum(.basalEnergyBurned, .kilocalorie(), from: d7, to: startOfDay)
        async let active28 = sum(.activeEnergyBurned, .kilocalorie(), from: d28, to: startOfDay)
        async let steps = sum(.stepCount, .count(), from: startOfDay, to: now)
        async let hrv = latest(.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli), since: cal.date(byAdding: .hour, value: -36, to: now)!)
        async let hrvBase = average(.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli), from: d28, to: startOfDay)
        async let rhr = latest(.restingHeartRate, .count().unitDivided(by: .minute()), since: cal.date(byAdding: .hour, value: -36, to: now)!)
        async let rhrBase = average(.restingHeartRate, .count().unitDivided(by: .minute()), from: d28, to: startOfDay)
        async let vo2 = latest(.vo2Max, HKUnit(from: "ml/kg*min"), since: cal.date(byAdding: .day, value: -60, to: now)!)
        async let sleep = lastNightSleep(now: now)
        async let mass = samples(.bodyMass, .gramUnit(with: .kilo), from: d21, to: now)

        let (a7, r7, a28, aToday) = await (active7, resting7, active28, activeToday)
        let hasWatchData = a7 > 0
        let estimate = NutritionEngine.estimatedEnergy(for: spec)
        let energy = hasWatchData
            ? EnergySnapshot(restingKcal: r7 > 0 ? r7 / 7 : estimate.restingKcal,
                             activeKcalToday: aToday,
                             activeKcal7DayAvg: a7 / 7,
                             isMeasured: true)
            : estimate

        let s = await sleep
        let recovery = RecoverySignals(
            hrvMs: await hrv, hrvBaselineMs: await hrvBase,
            restingHR: await rhr, restingHRBaseline: await rhrBase,
            sleepHours: s.total, deepSleepHours: s.deep, remSleepHours: s.rem,
            acuteLoad: hasWatchData ? a7 / 7 : nil,
            chronicLoad: a28 > 0 ? a28 / 28 : nil,
            vo2Max: await vo2)

        let weights = await mass
        return DaySnapshot(energy: energy, recovery: recovery, steps: await steps,
                           bodyMass: weights, weeklyWeightChange: Self.weeklySlope(weights))
    }

    // MARK: - Writing

    func save(meal: Macros, at date: Date) async {
        guard isAvailable else { return }
        let pairs: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), meal.kcal),
            (.dietaryProtein, .gram(), meal.protein),
            (.dietaryCarbohydrates, .gram(), meal.carbs),
            (.dietaryFatTotal, .gram(), meal.fat),
        ]
        let samples = pairs.filter { $0.2 > 0 }.map {
            HKQuantitySample(type: HKQuantityType($0.0), quantity: HKQuantity(unit: $0.1, doubleValue: $0.2), start: date, end: date)
        }
        try? await store.save(samples)
    }

    // MARK: - Query helpers

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from: Date, to: Date) async -> Double {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: from, end: to))
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        return (try? await query.result(for: store))?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    private func average(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from: Date, to: Date) async -> Double? {
        let type = HKQuantityType(id)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: from, end: to))
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .discreteAverage)
        return (try? await query.result(for: store))?.averageQuantity()?.doubleValue(for: unit)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, since: Date) async -> Double? {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        return (try? await query.result(for: store))?.first?.quantity.doubleValue(for: unit)
    }

    private func samples(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from: Date, to: Date) async -> [(date: Date, kg: Double)] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)])
        let result = (try? await query.result(for: store)) ?? []
        return result.map { (date: $0.startDate, kg: $0.quantity.doubleValue(for: unit)) }
    }

    /// Sleep between 6 pm yesterday and noon today, split by stage (watchOS 9+ staging).
    private func lastNightSleep(now: Date) async -> (total: Double?, deep: Double?, rem: Double?) {
        let cal = Calendar.current
        let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: now)!)!
        let end = min(now, cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!)
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [])
        guard let samples = try? await query.result(for: store), !samples.isEmpty else { return (nil, nil, nil) }

        // Prefer the Watch's staged data; fall back to anything "asleep" from other sources.
        var total = 0.0, deep = 0.0, rem = 0.0
        for s in samples {
            guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let h = s.endDate.timeIntervalSince(s.startDate) / 3600
            switch v {
            case .asleepDeep: deep += h; total += h
            case .asleepREM: rem += h; total += h
            case .asleepCore, .asleepUnspecified: total += h
            default: break
            }
        }
        return total > 0 ? (total, deep > 0 ? deep : nil, rem > 0 ? rem : nil) : (nil, nil, nil)
    }

    static func weeklySlope(_ points: [(date: Date, kg: Double)]) -> Double? {
        guard points.count >= 5, let first = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        return den > 0 ? num / den * 7 : nil
    }
}
