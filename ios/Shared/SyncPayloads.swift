import Foundation

/// iPhone → Watch: the day's summary, sent as WatchConnectivity application context.
struct WatchDayContext: Codable, Sendable {
    var profileName: String
    var readiness: Int
    var readinessBand: String
    var proteinLeft: Double
    var kcalLeft: Double
    var session: PlannedSession
    var updatedAt: Date
}

struct PlannedSession: Codable, Hashable, Sendable {
    struct Exercise: Codable, Hashable, Identifiable, Sendable {
        var name: String
        var sets: Int
        var target: String       // "5 reps", "4 min", "45 s"
        var weightKg: Double?    // nil for bodyweight / cardio
        var id: String { name }
    }
    var title: String
    var intensity: String
    var exercises: [Exercise]
}

/// Watch → iPhone: one completed set, delivered with transferUserInfo so it survives
/// the phone being out of range.
struct SetLogMessage: Codable, Sendable {
    var exercise: String
    var setIndex: Int
    var reps: Int?
    var weightKg: Double?
    var date: Date

    static let key = "setLog"
}

enum SyncCoding {
    static func encode<T: Encodable>(_ v: T) -> Data? { try? JSONEncoder().encode(v) }
    static func decode<T: Decodable>(_ t: T.Type, from d: Any?) -> T? {
        guard let d = d as? Data else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }
}
