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
        let m = targets.macros

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenHeader(title: "Rest of today",
                                 subtitle: "\(profile.spec.goal.title), \(profile.spec.diet.label.lowercased()). Rebuilt after every meal you log.")

                    VStack(alignment: .leading, spacing: 16) {
                        Text("These meals close the day at \(Int(m.kcal)) kcal: \(Int(m.protein)) g protein, \(Int(m.carbs)) g carbs, \(Int(m.fat)) g fat\(targets.isTrainingDay ? ", with carbs raised for training" : "").")
                            .font(.footnote).foregroundStyle(Theme.ink2)

                        VStack(spacing: 0) {
                            ForEach(Array(meals.enumerated()), id: \.element.id) { i, meal in
                                TimelineRow(time: meal.time, planned: true, isFirst: i == 0, isLast: i == meals.count - 1) {
                                    Text(meal.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                                    Text(meal.items.map { "\(Int($0.grams)) g \($0.food.name.lowercased())" }.joined(separator: ", "))
                                        .font(.footnote).foregroundStyle(Theme.ink2)
                                    Button("Log as eaten") {
                                        model.log(meal.items.map { ($0.food, grams: $0.grams, volume: nil) }, name: meal.name, source: .plan, for: profile)
                                    }
                                    .buttonStyle(.helix(.quiet, small: true))
                                    .padding(.top, 6)
                                } trailing: {
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(Int(meal.macros.kcal), format: .number).font(.figure(14)).foregroundStyle(Theme.ink)
                                        Text("\(Int(meal.macros.protein)) g protein").font(.system(size: 12)).foregroundStyle(Theme.ink2)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)

                    let groceries = MealPlanner.groceryList(from: meals)
                    if !groceries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("Shopping for five days like this")
                            VStack(spacing: 0) {
                                ForEach(Array(groceries.enumerated()), id: \.element.id) { i, item in
                                    HStack {
                                        Text(item.food.name).foregroundStyle(Theme.ink)
                                        Spacer()
                                        Text(item.grams >= 1000 ? String(format: "%.1f kg", item.grams / 1000) : "\(Int(item.grams)) g")
                                            .font(.figure(14, weight: .regular)).foregroundStyle(Theme.ink2)
                                    }
                                    .font(.system(size: 15))
                                    .padding(.vertical, 9)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.rule).frame(height: 1) } }
                                }
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.top, Theme.sectionGap)
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Theme.fog)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
