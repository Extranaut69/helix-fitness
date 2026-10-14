import SwiftUI
import SwiftData

@main
struct HelixApp: App {
    let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container = try! ModelContainer(for: UserProfile.self, MealLog.self, LoggedFood.self, LoggedSet.self)
        self.container = container
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.action)
        }
        .modelContainer(container)
    }
}
