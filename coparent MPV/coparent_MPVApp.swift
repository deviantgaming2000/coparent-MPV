import SwiftUI

@main
struct coparent_MPVApp: App {
    @State private var account = AccountManager()
    @State private var entitlements = EntitlementManager()
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
            .environment(entitlements)
        }
    }
}
