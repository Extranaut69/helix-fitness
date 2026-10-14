import Foundation
import SwiftData
import WatchConnectivity

/// Sends the day's summary to the Watch and stores sets logged on the Watch.
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func send(_ context: WatchDayContext) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled,
              let data = SyncCoding.encode(context) else { return }
        try? WCSession.default.updateApplicationContext(["day": data])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let msg = SyncCoding.decode(SetLogMessage.self, from: userInfo[SetLogMessage.key]) else { return }
        Task { @MainActor in
            let ctx = container.mainContext
            let activeID = UserDefaults.standard.string(forKey: "activeProfileID").flatMap(UUID.init(uuidString:))
            let profiles = (try? ctx.fetch(FetchDescriptor<UserProfile>())) ?? []
            guard let owner = profiles.first(where: { $0.id == activeID }) ?? profiles.first(where: \.usesHealthKit) else { return }
            let set = LoggedSet(exercise: msg.exercise, setIndex: msg.setIndex, reps: msg.reps, weightKg: msg.weightKg, date: msg.date)
            set.profile = owner
            ctx.insert(set)
            try? ctx.save()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
