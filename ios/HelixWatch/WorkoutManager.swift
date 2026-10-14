import Foundation
import HealthKit
import Observation

/// Runs an HKWorkoutSession with live heart rate and energy, saved to Health when finished.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var isRunning = false
    private(set) var heartRate: Double = 0
    private(set) var activeKcal: Double = 0
    private(set) var startDate: Date?
    /// Seconds spent in each of 5 heart-rate zones (based on 220 − age max HR).
    private(set) var zoneSeconds = [Double](repeating: 0, count: 5)
    var maxHR: Double = 190
    private var lastSample: Date?

    func start(activity: HKWorkoutActivityType) async {
        let types: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.heartRate)]
        try? await store.requestAuthorization(toShare: types, read: types)

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = activity == .running ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            zoneSeconds = Array(repeating: 0, count: 5)
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    func end() async {
        guard let session, let builder else { return }
        session.end()
        try? await builder.endCollection(at: .now)
        _ = try? await builder.finishWorkout()
        isRunning = false
        self.session = nil
        self.builder = nil
    }

    func zone(for hr: Double) -> Int {
        let pct = hr / maxHR
        switch pct {
        case ..<0.6: return 0
        case ..<0.7: return 1
        case ..<0.8: return 2
        case ..<0.9: return 3
        default: return 4
        }
    }

    fileprivate func update(hr: Double?, kcal: Double?) {
        if let hr {
            let now = Date.now
            if let last = lastSample, heartRate > 0 { zoneSeconds[zone(for: heartRate)] += now.timeIntervalSince(last) }
            lastSample = now
            heartRate = hr
        }
        if let kcal { activeKcal = kcal }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hr = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in self.update(hr: hr, kcal: kcal) }
    }
}
