import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var tab = Tab.today
    @State private var showProfiles = false

    enum Tab: Hashable { case today, train, scan, coach, plan }

    var body: some View {
        Group {
            if let profile = model.activeProfile(in: profiles) {
                TabView(selection: $tab) {
                    TodayView(profile: profile, showProfiles: $showProfiles,
                              openScan: { tab = .scan }, openTrain: { tab = .train }, openPlan: { tab = .plan })
                        .tabItem { Label("Today", systemImage: "sun.horizon") }.tag(Tab.today)
                    TrainView(profile: profile)
                        .tabItem { Label("Train", systemImage: "dumbbell") }.tag(Tab.train)
                    ScanView(profile: profile, onLogged: { tab = .today })
                        .tabItem { Label("Scan", systemImage: "viewfinder") }.tag(Tab.scan)
                    CoachView(profile: profile)
                        .tabItem { Label("Coach", systemImage: "text.bubble") }.tag(Tab.coach)
                    PlanView(profile: profile)
                        .tabItem { Label("Plan", systemImage: "list.bullet") }.tag(Tab.plan)
                }
                .sheet(isPresented: $showProfiles) { ProfilesView() }
                .task(id: profile.id) { await model.refresh(profile) }
            } else {
                OnboardingView(isFirstProfile: true) { _ in }
            }
        }
        .background(Theme.fog.ignoresSafeArea())
    }
}
