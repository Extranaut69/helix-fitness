import Foundation

/// Raw recovery inputs. Any value can be missing (new watch, no sleep tracking); missing
/// signals score neutral instead of punishing the user.
struct RecoverySignals: Codable, Sendable {
    var hrvMs: Double?
    var hrvBaselineMs: Double?
    var restingHR: Double?
    var restingHRBaseline: Double?
    var sleepHours: Double?
    var deepSleepHours: Double?
    var remSleepHours: Double?
    var sleepNeedHours: Double = 8
    /// 7-day average daily active energy.
    var acuteLoad: Double?
    /// 28-day average daily active energy.
    var chronicLoad: Double?
    var vo2Max: Double?
}

struct Readiness: Codable, Sendable {
    struct Component: Codable, Identifiable, Sendable {
        var name: String
        var score: Double
        var id: String { name }
    }

    enum Band: String, Codable, Sendable {
        case primed, steady, recover

        init(score: Int) { self = score >= 75 ? .primed : score >= 55 ? .steady : .recover }

        /// Short name, used on the Watch and in the coach prompt.
        var title: String {
            switch self {
            case .primed: "Go hard"
            case .steady: "Train as planned"
            case .recover: "Recovery day"
            }
        }

        /// The sentence the Today screen leads with on a training day.
        var headline: String {
            switch self {
            case .primed: "Go hard today."
            case .steady: "Train as planned."
            case .recover: "Take a recovery day."
            }
        }
    }

    var score: Int
    var components: [Component]
    var loadRatio: Double?

    var band: Band { Band(score: score) }
    var weakest: Component? { components.min { $0.score < $1.score } }
}

enum ReadinessEngine {
    static func evaluate(_ s: RecoverySignals) -> Readiness {
        func clamp(_ v: Double) -> Double { min(100, max(0, v)) }
        let neutral = 60.0

        let hrv: Double = {
            guard let v = s.hrvMs, let b = s.hrvBaselineMs, b > 0 else { return neutral }
            return clamp(50 + (v - b) / b * 250)          // +10 % vs baseline → 75
        }()
        let rhr: Double = {
            guard let v = s.restingHR, let b = s.restingHRBaseline else { return neutral }
            return clamp(60 - (v - b) * 9)                // each bpm above baseline costs 9
        }()
        let sleep: Double = {
            guard let h = s.sleepHours else { return neutral }
            return clamp(h / s.sleepNeedHours * 100)
        }()
        var ratio: Double?
        let load: Double = {
            guard let a = s.acuteLoad, let c = s.chronicLoad, c > 0 else { return neutral }
            let r = a / c
            ratio = r
            if r < 0.8 { return 75 }                        // detraining, but fresh
            if r <= 1.3 { return 92 }                       // sweet spot
            return max(20, 92 - (r - 1.3) * 160)            // spike → injury risk
        }()

        let score = hrv * 0.35 + rhr * 0.20 + sleep * 0.30 + load * 0.15
        return Readiness(
            score: Int(score.rounded()),
            components: [
                .init(name: "HRV", score: hrv),
                .init(name: "Resting HR", score: rhr),
                .init(name: "Sleep", score: sleep),
                .init(name: "Load", score: load),
            ],
            loadRatio: ratio
        )
    }
}
