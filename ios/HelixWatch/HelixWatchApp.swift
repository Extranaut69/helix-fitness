import SwiftUI

@main
struct HelixWatchApp: App {
    @State private var link = WatchLink()
    @State private var workout = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchHomeView()
            }
            .environment(link)
            .environment(workout)
            .tint(Palette.actionOnDark)
        }
    }
}
