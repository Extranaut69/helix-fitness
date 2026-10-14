import Foundation
import WatchConnectivity
import Observation

/// Receives the day's summary from the iPhone and sends completed sets back.
@MainActor
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    private(set) var day: WatchDayContext?

    override init() {
        super.init()
        if let cached = UserDefaults.standard.data(forKey: "day") { day = try? JSONDecoder().decode(WatchDayContext.self, from: cached) }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func logSet(exercise: String, index: Int, reps: Int?, weightKg: Double?) {
        let msg = SetLogMessage(exercise: exercise, setIndex: index, reps: reps, weightKg: weightKg, date: .now)
        guard let data = SyncCoding.encode(msg) else { return }
        WCSession.default.transferUserInfo([SetLogMessage.key: data])
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext ctx: [String: Any]) {
        guard let data = ctx["day"] as? Data else { return }
        Task { @MainActor in
            self.day = try? JSONDecoder().decode(WatchDayContext.self, from: data)
            UserDefaults.standard.set(data, forKey: "day")
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { self.session(session, didReceiveApplicationContext: ctx) }
    }
}
