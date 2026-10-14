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
            .tint(Color(red: 0.498, green: 0.878, blue: 1.0))
        }
    }
}
