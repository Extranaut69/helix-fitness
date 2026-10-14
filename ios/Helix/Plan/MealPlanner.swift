import Foundation

/// Builds meals from the food table that close the gap to today's targets.
@MainActor
enum MealPlanner {
    struct PlannedMeal: Identifiable {
        var name: String
        var items: [(food: FoodInfo, grams: Double)]
        var id: String { name }
        var macros: Macros { items.reduce(.zero) { $0 + $1.food.macros(grams: $1.grams) } }
    }

    /// Splits what's left of today across the remaining meals.
    static func restOfDay(remaining: Macros, diet: Diet, now: Date = .now) -> [PlannedMeal] {
        let hour = Calendar.current.component(.hour, from: now)
        let slots: [(String, Double)] = switch hour {
        case ..<10: [("Lunch", 0.4), ("Snack", 0.15), ("Dinner", 0.45)]
        case ..<15: [("Snack", 0.25), ("Dinner", 0.75)]
        case ..<19: [("Dinner", 1.0)]
        default: [("Evening snack", 1.0)]
        }
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 0
        return slots.enumerated().map { i, slot in
            PlannedMeal(name: slot.0, items: meal(for: remaining.scaled(by: slot.1), diet: diet, rotation: seed + i * 3))
        }
    }

    /// Greedy fill: protein source first, then carbs, a vegetable, then fat.
    static func meal(for want: Macros, diet: Diet, rotation: Int) -> [(food: FoodInfo, grams: Double)] {
        let db = FoodDatabase.shared
        func pick(_ role: FoodInfo.Role, _ offset: Int) -> FoodInfo? {
            let options = db.foods(role: role, diet: diet)
            return options.isEmpty ? nil : options[(rotation + offset) % options.count]
        }
        func clampRound(_ g: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, (g / 5).rounded() * 5)) }

        var items: [(food: FoodInfo, grams: Double)] = []
        var have = Macros.zero
        func add(_ f: FoodInfo, _ g: Double) {
            guard g > 0 else { return }
            items.append((f, g)); have = have + f.macros(grams: g)
        }

        if let pro = pick(.protein, 0), pro.per100g.protein > 0 {
            add(pro, clampRound(max(15, want.protein) / pro.per100g.protein * 100, 30, 300))
        }
        if let carb = pick(.carb, 1), carb.per100g.carbs > 0 {
            add(carb, clampRound((want.carbs - have.carbs) / carb.per100g.carbs * 100, 0, 350))
        }
        if let veg = pick(.veg, 0) { add(veg, 100) }
        if let fat = pick(.fat, 2), fat.per100g.fat > 0 {
            add(fat, clampRound((want.fat - have.fat) / fat.per100g.fat * 100, 0, 60))
        }
        return items
    }

    /// Five days of the current plan, summed by food.
    struct GroceryItem: Identifiable {
        var food: FoodInfo
        var grams: Double
        var id: String { food.id }
    }

    static func groceryList(from meals: [PlannedMeal], days: Int = 5) -> [GroceryItem] {
        var totals: [String: GroceryItem] = [:]
        for m in meals {
            for it in m.items { totals[it.food.id, default: GroceryItem(food: it.food, grams: 0)].grams += it.grams * Double(days) }
        }
        return totals.values.sorted { $0.food.name < $1.food.name }
    }
}
