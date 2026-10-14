import Foundation

/// Offline nutrition table bundled with the app (USDA FoodData Central reference values).
/// Extend `foods.json` freely; see README for importing the full USDA dataset.
@MainActor
final class FoodDatabase {
    static let shared = FoodDatabase()

    private(set) var foods: [FoodInfo] = []
    private var byID: [String: FoodInfo] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FoodInfo].self, from: data) else { return }
        foods = decoded
        byID = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    subscript(id: String) -> FoodInfo? { byID[id] }

    func foods(role: FoodInfo.Role, diet: Diet) -> [FoodInfo] {
        foods.filter { $0.role == role && diet.allows($0) }
    }

    /// Maps a classifier label (e.g. "fried_rice", "Chicken Curry") to a food, best match first.
    func match(label raw: String) -> FoodInfo? {
        let label = raw.replacingOccurrences(of: "_", with: " ").lowercased().trimmingCharacters(in: .whitespaces)
        if let exact = foods.first(where: { $0.aliases.contains(label) || $0.name.lowercased() == label }) { return exact }
        // Partial match: longest alias contained in the label wins ("chicken tikka masala" → chicken).
        var best: (FoodInfo, Int)?
        for f in foods {
            for a in f.aliases where label.contains(a) && a.count > (best?.1 ?? 0) { best = (f, a.count) }
        }
        return best?.0
    }

    func search(_ text: String) -> [FoodInfo] {
        let q = text.lowercased()
        guard !q.isEmpty else { return foods }
        return foods.filter { $0.name.lowercased().contains(q) || $0.aliases.contains { $0.contains(q) } }
    }
}
