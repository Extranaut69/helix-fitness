import SwiftUI

struct PlanView: View {
    @Environment(AppModel.self) private var model
    let profile: UserProfile

    var body: some View {
        let targets = model.targets(for: profile)
        let remaining = model.remaining(for: profile)
        let meals = MealPlanner.restOfDay(remaining: Macros(kcal: max(0, remaining.kcal), protein: max(0, remaining.protein),
                                                            carbs: max(0, remaining.carbs), fat: max(0, remaining.fat)),
                                          diet: profile.spec.diet)

        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Card {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Planned to close the day at").font(.caption).foregroundStyle(Theme.mute)
                                Text("\(Int(targets.macros.kcal)) kcal").font(.data(22))
                            }
                            Spacer()
                            Text("\(Int(targets.macros.protein)) P · \(Int(targets.macros.carbs)) C · \(Int(targets.macros.fat)) F")
                                .font(.data(12)).foregroundStyle(Theme.mute)
                        }
                    }
                    ForEach(meals) { meal in
                        Card {
                            HStack {
                                Text(meal.name).font(.headline)
                                Spacer()
                                Text("\(Int(meal.macros.kcal)) kcal · \(Int(meal.macros.protein)) P").font(.data(12)).foregroundStyle(Theme.mute)
                            }
                            Text(meal.items.map { "\(Int($0.grams)) g \($0.food.name.lowercased())" }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(Theme.mute)
                            Button("Log as eaten") {
                                model.log(meal.items.map { ($0.food, grams: $0.grams, volume: nil) }, name: meal.name, source: .plan, for: profile)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Card {
                        Eyebrow("5-day grocery list")
                        ForEach(MealPlanner.groceryList(from: meals)) { item in
                            HStack {
                                Text(item.food.name)
                                Spacer()
                                Text(item.grams >= 1000 ? String(format: "%.1f kg", item.grams / 1000) : "\(Int(item.grams)) g")
                                    .font(.data(12)).foregroundStyle(Theme.mute)
                            }
                        }
                    }
                    Text("The plan is rebuilt after every meal you log, so it always fits what's left of today.")
                        .font(.caption).foregroundStyle(Theme.mute)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Meal plan")
        }
    }
}
