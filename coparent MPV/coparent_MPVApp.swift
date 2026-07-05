import SwiftUI

@main
struct coparent_MPVApp: App {
    @State private var account = AccountManager()
    @AppStorage("coparoHasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingContainerView()
                }
            }
            .environment(account)
        }
    }
}
