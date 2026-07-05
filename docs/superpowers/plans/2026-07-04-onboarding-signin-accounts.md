# Onboarding, Sign-in, and Accounts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the reference app's first-run onboarding as a native SwiftUI flow (splash, account, welcome, custody, mode, people, complete) with working Sign in with Apple, a "coming soon" Google button, an optional skip, and a real Account screen in the menu.

**Architecture:** A single `OnboardingContainerView` drives an ordered set of full-screen steps with slide transitions, gated at the app root by `@AppStorage("coparoHasCompletedOnboarding")`. Account identity lives in an `@Observable AccountManager` (backed by `AccountStore` in UserDefaults) injected through the SwiftUI environment so `ContentView` and `SettingsView` can read it. The custody, mode, and people steps write to the app's existing stores.

**Tech Stack:** SwiftUI (iOS 26), `AuthenticationServices` (`SignInWithAppleButton`), the Observation framework (`@Observable`), `@AppStorage`/UserDefaults, existing `FactTrailTheme` design tokens.

## Global Constraints

- Never use the em dash "-". Use a plain dash "-" in all code comments and UI copy.
- New Swift files must be created inside the `coparent MPV/` folder, which is a `PBXFileSystemSynchronizedRootGroup` that auto-includes them in the target. Do not edit the `.pbxproj` to add source files.
- Match the reference theme, which already corresponds to `FactTrailTheme`: primary `#2F5D8C`, accent `#4F8F8B`, surface `#FFFFFF`, bg `#F7F4EF`, border `#E5E1DA`, text-primary `#172033`, text-secondary `#4B5563`, text-muted `#6B7280`. Always resolve colors through `FactTrailTheme` accessors, never hardcode, so dark mode keeps working.
- The account is a local identity only. There is no backend. No email/password, no Google flow, no network calls.
- Bundle id is `mike.coparent-MPV`. Development team `N4D8948SYX`, automatic signing.
- Build with:
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "/Users/mikehansen/Desktop/coparent MPV/coparent MPV.xcodeproj" -scheme "coparent MPV" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
  ```
  A passing task ends with `** BUILD SUCCEEDED **`.
- There is no unit-test target and Sign in with Apple cannot complete on a plain simulator. The test cycle for each task is: build succeeds, then a concrete runtime check on the booted simulator (install with `xcrun simctl install booted <AppPath>` and launch with `xcrun simctl launch booted mike.coparent-MPV`). Apple sign-in success is verified on a physical device; note that explicitly where it applies.
- To reach first-run onboarding repeatedly during testing, reset the flag between runs with:
  ```
  xcrun simctl spawn booted defaults delete mike.coparent-MPV coparoHasCompletedOnboarding 2>/dev/null; true
  ```
  (or use the app's Reset all data once Task 8 lands.)

---

## File Structure

- Create `coparent MPV/AccountSession.swift` - account identity: `AccountProvider`, `AccountSession`, `AccountStore`, `AccountManager`.
- Create `coparent MPV/OnboardingFlow.swift` - `OnboardingStep`, `OnboardingContainerView`, the seven step subviews, and shared onboarding UI components (`OBScaffold`, `OBIconRing`, `OBPrimaryButton`, `OBChoiceRow`, `OBProgressRow`, `OBSkipRow`).
- Create `coparent MPV/AccountView.swift` - the menu's Account screen.
- Modify `coparent MPV/coparent_MPVApp.swift` - root gate + environment injection.
- Modify `coparent MPV/coparent_MPV.entitlements` - add the Sign in with Apple entitlement.
- Modify `coparent MPV/SettingsView.swift` - profile row reflects the session; Account row opens `AccountView`.
- Modify `coparent MPV/ContentView.swift` - home sign-in banner; extend `resetAllData()`.

---

## Task 1: Sign in with Apple entitlement + Account model, store, manager

**Files:**
- Modify: `coparent MPV/coparent_MPV.entitlements`
- Create: `coparent MPV/AccountSession.swift`

**Interfaces:**
- Produces:
  - `enum AccountProvider: String, Codable { case apple, google }`
  - `struct AccountSession: Codable, Equatable { var provider: AccountProvider; var userID: String; var displayName: String?; var email: String?; var signedInAt: Date }`
  - `enum AccountStore { static func load() -> AccountSession?; static func save(_:); static func clear() }`
  - `@Observable final class AccountManager { var session: AccountSession?; var isSignedIn: Bool; var displayName: String?; var email: String?; func applyAppleCredential(userID: String, fullName: PersonNameComponents?, email: String?, at now: Date); func signOut() }`

- [ ] **Step 1: Add the Sign in with Apple entitlement**

Replace the whole contents of `coparent MPV/coparent_MPV.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.applesignin</key>
	<array>
		<string>Default</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 2: Create the account model, store, and manager**

Create `coparent MPV/AccountSession.swift`:

```swift
import Foundation
import Observation

/// Where an account identity came from. Google is defined for parity with the
/// reference UI but is not wired to a real flow yet.
enum AccountProvider: String, Codable {
    case apple
    case google
}

/// A local account identity. There is no backend, so this only records who the
/// user is for display; it does not sync or protect data server-side.
struct AccountSession: Codable, Equatable {
    var provider: AccountProvider
    var userID: String
    var displayName: String?
    var email: String?
    var signedInAt: Date
}

/// Persists a single account session in UserDefaults.
enum AccountStore {
    static let key = "coparoAccountSession"

    static func load() -> AccountSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccountSession.self, from: data)
    }

    static func save(_ session: AccountSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Observable holder for the current account, shared through the SwiftUI
/// environment. Created once at app root.
@Observable
final class AccountManager {
    var session: AccountSession?

    init() {
        session = AccountStore.load()
    }

    var isSignedIn: Bool { session != nil }
    var displayName: String? { session?.displayName }
    var email: String? { session?.email }

    /// Build and persist a session from an Apple credential. Apple returns the
    /// name and email only on the first authorization, so keep whatever is given.
    /// When a name is present and the user has no saved name yet, seed it so the
    /// greeting and profile row reflect it.
    func applyAppleCredential(userID: String, fullName: PersonNameComponents?, email: String?, at now: Date = Date()) {
        let formatter = PersonNameComponentsFormatter()
        let formattedName = fullName
            .map { formatter.string(from: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (formattedName?.isEmpty == false) ? formattedName : nil

        let newSession = AccountSession(
            provider: .apple,
            userID: userID,
            displayName: name,
            email: email,
            signedInAt: now
        )
        session = newSession
        AccountStore.save(newSession)

        if let name {
            let existing = (UserDefaults.standard.string(forKey: "factTrailUserName") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if existing.isEmpty {
                UserDefaults.standard.set(name, forKey: "factTrailUserName")
            }
        }
    }

    func signOut() {
        session = nil
        AccountStore.clear()
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project "/Users/mikehansen/Desktop/coparent MPV/coparent MPV.xcodeproj" -scheme "coparent MPV" -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`. The new file compiles and the entitlement is picked up.

- [ ] **Step 4: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/AccountSession.swift" "coparent MPV/coparent_MPV.entitlements"
git commit -m "Add account model, store, manager, and Sign in with Apple entitlement"
```

---

## Task 2: Onboarding scaffold - gate, splash, account, welcome, complete, shared components

**Files:**
- Create: `coparent MPV/OnboardingFlow.swift`
- Modify: `coparent MPV/coparent_MPVApp.swift`

**Interfaces:**
- Consumes: `AccountManager` (Task 1).
- Produces:
  - `struct OnboardingContainerView: View` (reads `@Environment(AccountManager.self)` and `@AppStorage("coparoHasCompletedOnboarding")`).
  - Shared components reused by Tasks 3-5: `OBScaffold`, `OBIconRing(system:)`, `OBPrimaryButton(title:action:)`, `OBChoiceRow(icon:title:subtitle:selected:action:)`, `OBProgressRow(step:total:)`, `OBSkipRow(action:)`.
  - `enum OnboardingStep: Int, CaseIterable { case splash, account, welcome, custody, mode, people, complete }`

- [ ] **Step 1: Create the onboarding flow file with the container, shared components, and the splash/account/welcome/complete screens plus navigational stubs for custody/mode/people**

Create `coparent MPV/OnboardingFlow.swift`:

```swift
import SwiftUI
import AuthenticationServices

// MARK: - Step model

enum OnboardingStep: Int, CaseIterable {
    case splash, account, welcome, custody, mode, people, complete
}

// MARK: - Container

struct OnboardingContainerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("coparoHasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var step: OnboardingStep = .splash

    var body: some View {
        ZStack {
            FactTrailTheme.background(for: colorScheme).ignoresSafeArea()

            content
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
        }
        .animation(.easeInOut(duration: 0.35), value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .splash:
            OnboardingSplash(onContinue: advance)
        case .account:
            OnboardingAccount(onSignedIn: advance, onSkip: advance)
        case .welcome:
            OnboardingWelcome(onContinue: advance)
        case .custody:
            OnboardingCustodyStep(onContinue: advance)
        case .mode:
            OnboardingModeStep(onContinue: advance)
        case .people:
            OnboardingPeopleStep(onContinue: advance)
        case .complete:
            OnboardingComplete(onFinish: finish)
        }
    }

    private func advance() {
        let all = OnboardingStep.allCases
        if let idx = all.firstIndex(of: step), idx + 1 < all.count {
            step = all[idx + 1]
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
    }
}

// MARK: - Shared components

/// Standard step layout: 24pt horizontal padding, scrollable content, primary
/// action pinned to the bottom. Mirrors the reference `.ob-content`.
struct OBScaffold<Content: View, Bottom: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
            bottom
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }
}

/// Accent-tinted rounded icon tile used at the top of most steps.
struct OBIconRing: View {
    let system: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12))
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: system)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            )
            .padding(.top, 18)
            .padding(.bottom, 20)
    }
}

/// Gradient primary button matching `.ob-primary-btn`.
struct OBPrimaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    LinearGradient(
                        colors: FactTrailTheme.primaryButtonColors(for: colorScheme),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: FactTrailTheme.primaryAction(for: colorScheme).opacity(0.28), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// A bordered choice card matching `.ob-choice-btn`.
struct OBChoiceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var selected: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FactTrailTheme.surface(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Four-segment progress bar matching `.ob-progress-row`. `step` is 1-based.
struct OBProgressRow: View {
    let step: Int
    var total: Int = 4
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(color(for: i))
                    .frame(height: 4)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private func color(for index: Int) -> Color {
        if index < step - 1 { return FactTrailTheme.aiAccent(for: colorScheme) }
        if index == step - 1 { return FactTrailTheme.primaryAction(for: colorScheme) }
        return FactTrailTheme.border(for: colorScheme)
    }
}

/// Right-aligned muted "Skip" row matching `.ob-skip-row`.
struct OBSkipRow: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            Spacer()
            Button("Skip", action: action)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

// MARK: - Splash

struct OnboardingSplash: View {
    let onContinue: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x2F5D8C), Color(hex: 0x3D7A8C), Color(hex: 0x4F8F8B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 84, height: 84)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(.white)
                    )
                    .padding(.bottom, 22)
                Text("Coparo")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
                Text("A clear record, quietly kept.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(i == 0 ? Color.white : Color.white.opacity(0.35))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onContinue)
        .task {
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) { appeared = true }
            try? await Task.sleep(for: .seconds(2.7))
            onContinue()
        }
    }
}

// MARK: - Account

struct OnboardingAccount: View {
    let onSignedIn: () -> Void
    let onSkip: () -> Void

    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var showGoogleNote = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            FactTrailTheme.background(for: colorScheme).ignoresSafeArea()

            // Header banner
            LinearGradient(
                colors: [Color(hex: 0x2F5D8C), Color(hex: 0x4F8F8B)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 220)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous))
            .ignoresSafeArea(edges: .top)

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                            .frame(width: 52, height: 52)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            )
                            .overlay(
                                Image(systemName: "heart")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundStyle(.white)
                            )
                            .padding(.bottom, 16)
                        Text("Glad you're here.\nLet's get you set up.")
                            .font(.system(size: 22, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text("Your records stay private and secure.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .padding(.top, 44)
                    .padding(.bottom, 28)

                    // Card
                    VStack(spacing: 10) {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleApple(result)
                        }
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            withAnimation { showGoogleNote = true }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "g.circle")
                                    .font(.system(size: 17, weight: .medium))
                                Text("Continue with Google")
                                    .font(.system(size: 14.5, weight: .semibold))
                            }
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(FactTrailTheme.surface(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if showGoogleNote {
                            Text("Google sign-in is coming soon.")
                                .font(.system(size: 12))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)
                        }

                        Button("Skip for now", action: onSkip)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .buttonStyle(.plain)
                            .padding(.top, 6)

                        Text("By continuing, you agree to our Terms and Privacy Policy.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 22)
                    .padding(.bottom, 20)
                    .background(FactTrailTheme.surface(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Could not read the Apple credential. Please try again."
                return
            }
            account.applyAppleCredential(
                userID: credential.user,
                fullName: credential.fullName,
                email: credential.email
            )
            onSignedIn()
        case .failure(let error):
            // A user cancel is silent; anything else surfaces a short message.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Sign in with Apple didn't complete. Please try again."
        }
    }
}

// MARK: - Welcome

struct OnboardingWelcome: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("factTrailUserName") private var userName = ""

    private var greeting: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Welcome to Coparo." : "Welcome, \(trimmed)."
    }

    var body: some View {
        OBScaffold {
            OBIconRing(system: "heart")
            Text(greeting)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 10)
            Text("Just a few questions before we get started - each one takes a few seconds, and you can skip anything you're not ready for.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        } bottom: {
            OBPrimaryButton(title: "Let's go", action: onContinue)
        }
    }
}

// MARK: - Custody / Mode / People (navigational stubs, fleshed out in later tasks)

struct OnboardingCustodyStep: View {
    let onContinue: () -> Void
    var body: some View {
        OBScaffold {
            OBProgressRow(step: 2)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "calendar")
            Text("Add your custody schedule?").font(.system(size: 22, weight: .bold))
        } bottom: {
            OBPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

struct OnboardingModeStep: View {
    let onContinue: () -> Void
    var body: some View {
        OBScaffold {
            OBProgressRow(step: 3)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "shield")
            Text("How should we prepare your records?").font(.system(size: 22, weight: .bold))
        } bottom: {
            OBPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

struct OnboardingPeopleStep: View {
    let onContinue: () -> Void
    var body: some View {
        OBScaffold {
            OBProgressRow(step: 4)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "person.2")
            Text("Add people you'll reference").font(.system(size: 22, weight: .bold))
        } bottom: {
            OBPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

// MARK: - Complete

struct OnboardingComplete: View {
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var popped = false

    var body: some View {
        OBScaffold {
            VStack(spacing: 0) {
                Circle()
                    .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.14))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    )
                    .scaleEffect(popped ? 1 : 0.6)
                    .padding(.top, 40)
                    .padding(.bottom, 22)
                Text("You're all set.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .padding(.bottom, 10)
                Text("Your record starts now. Log fast when something happens - we'll help make sense of it over time.")
                    .font(.system(size: 14))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            OBPrimaryButton(title: "Go to Coparo", action: onFinish)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { popped = true }
        }
    }
}
```

- [ ] **Step 2: Gate the app on onboarding and inject the AccountManager**

Replace the whole contents of `coparent MPV/coparent_MPVApp.swift` with:

```swift
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
```

- [ ] **Step 3: Build**

Run the build command from Global Constraints.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run and verify the flow on the simulator**

Reset the flag, install, and launch:
```
xcrun simctl spawn booted defaults delete mike.coparent-MPV coparoHasCompletedOnboarding 2>/dev/null; true
```
Then install the freshly built app and launch it. Verify visually:
- The splash shows the Coparo mark on the blue/teal gradient and auto-advances after about 3 seconds.
- The account screen shows the teal banner, "Glad you're here. Let's get you set up.", the black Sign in with Apple button, the white "Continue with Google" button, "Skip for now", and the legal note.
- Tapping "Continue with Google" reveals "Google sign-in is coming soon." and does nothing else.
- Tapping "Skip for now" advances to "Welcome to Coparo." Tapping "Let's go" moves through the stub custody, mode, and people screens (each with a Skip and Continue) to "You're all set.", and "Go to Coparo" lands on the app home.
- Note: Sign in with Apple itself completes only on a physical device or a simulator signed into an Apple ID; on a plain simulator it may show the system sheet but not finish. That is expected.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/OnboardingFlow.swift" "coparent MPV/coparent_MPVApp.swift"
git commit -m "Add onboarding scaffold: gate, splash, account, welcome, complete"
```

---

## Task 3: Custody step

**Files:**
- Modify: `coparent MPV/OnboardingFlow.swift` (replace `OnboardingCustodyStep`)

**Interfaces:**
- Consumes: `OBScaffold`, `OBProgressRow`, `OBSkipRow`, `OBIconRing`, `OBChoiceRow` (Task 2); `CustodyScheduleView(userName:onSave:onTurnOff:)`, `CustodyScheduleStore` (existing).

- [ ] **Step 1: Replace `OnboardingCustodyStep` with the real step**

In `coparent MPV/OnboardingFlow.swift`, replace the entire `OnboardingCustodyStep` struct with:

```swift
struct OnboardingCustodyStep: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("factTrailUserName") private var userName = ""
    @State private var showingSetup = false

    var body: some View {
        OBScaffold {
            OBProgressRow(step: 2)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "calendar")
            Text("Add your custody schedule?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 10)
            Text("This helps us color-code your calendar automatically. You can always add or change it later.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                OBChoiceRow(icon: "checkmark", title: "Yes, let's add it", subtitle: "Choose a pattern and start date on the next screen.") {
                    showingSetup = true
                }
                OBChoiceRow(icon: "info.circle", title: "Not right now", subtitle: "You can set this up anytime from settings.") {
                    onContinue()
                }
            }
        } bottom: {
            EmptyView()
        }
        .sheet(isPresented: $showingSetup) {
            NavigationStack {
                CustodyScheduleView(
                    userName: userName,
                    onSave: { schedule in
                        CustodyScheduleStore.save(schedule)
                    },
                    onTurnOff: { CustodyScheduleStore.clear() }
                )
            }
            .onDisappear { onContinue() }
        }
    }
}
```

Note: `CustodyScheduleView` already dismisses itself on save and turn-off; its dismissal triggers `onDisappear`, which advances the wizard. If the user swipes the sheet away without saving, the wizard still advances, which is acceptable (equivalent to "Not right now").

- [ ] **Step 2: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify on the simulator**

Relaunch onboarding (reset flag, install, launch). Skip to the custody step. Verify:
- The step shows the four-segment progress bar (segment 2 highlighted), a Skip link, the calendar icon, the title and subtitle, and the two choice cards.
- "Yes, let's add it" opens the existing custody setup sheet. Saving a schedule returns and advances to the Mode step.
- "Not right now" and Skip both advance to the Mode step with no schedule saved.

- [ ] **Step 4: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/OnboardingFlow.swift"
git commit -m "Flesh out onboarding custody step with existing setup"
```

---

## Task 4: Mode step

**Files:**
- Modify: `coparent MPV/OnboardingFlow.swift` (replace `OnboardingModeStep`)

**Interfaces:**
- Consumes: `OBScaffold`, `OBProgressRow`, `OBSkipRow`, `OBIconRing`, `OBChoiceRow`, `OBPrimaryButton` (Task 2); `CoparoMode` and the `coparoMode` app setting (existing).

- [ ] **Step 1: Replace `OnboardingModeStep` with the real step**

In `coparent MPV/OnboardingFlow.swift`, replace the entire `OnboardingModeStep` struct with:

```swift
struct OnboardingModeStep: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("coparoMode") private var modeRaw = CoparoMode.casual.rawValue

    var body: some View {
        OBScaffold {
            OBProgressRow(step: 3)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "shield")
            Text("How should we prepare your records?")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 10)
            Text("This controls what happens quietly in the background. You can change it anytime from settings.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

            VStack(spacing: 10) {
                OBChoiceRow(
                    icon: "heart",
                    title: "Just keeping a record",
                    subtitle: "Log things as they happen, just in case you need them later.",
                    selected: modeRaw == CoparoMode.casual.rawValue
                ) {
                    modeRaw = CoparoMode.casual.rawValue
                }
                OBChoiceRow(
                    icon: "building.columns",
                    title: "I want my records court-ready",
                    subtitle: "We'll generate neutral, lawyer-ready summaries of your entries in the background.",
                    selected: modeRaw == CoparoMode.court.rawValue
                ) {
                    modeRaw = CoparoMode.court.rawValue
                }
            }
            .padding(.bottom, 16)
        } bottom: {
            OBPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}
```

- [ ] **Step 2: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify on the simulator**

Relaunch onboarding and reach the Mode step. Verify:
- Progress segment 3 highlighted, Skip present.
- Selecting a choice highlights its border. "Continue" advances to People.
- After finishing onboarding, open the menu and confirm the Mode row badge reflects the chosen mode (Casual or Court).

- [ ] **Step 4: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/OnboardingFlow.swift"
git commit -m "Flesh out onboarding mode step, wired to coparoMode"
```

---

## Task 5: People step

**Files:**
- Modify: `coparent MPV/OnboardingFlow.swift` (replace `OnboardingPeopleStep`)

**Interfaces:**
- Consumes: `OBScaffold`, `OBProgressRow`, `OBSkipRow`, `OBIconRing`, `OBPrimaryButton` (Task 2); `SavedPerson`, `PersonRole`, `PeopleStore` (existing).

- [ ] **Step 1: Replace `OnboardingPeopleStep` with the real step**

In `coparent MPV/OnboardingFlow.swift`, replace the entire `OnboardingPeopleStep` struct with:

```swift
struct OnboardingPeopleStep: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// One editable draft row. `roleOther` holds the free-text when role is `.other`.
    struct DraftPerson: Identifiable {
        let id = UUID()
        var name: String = ""
        var role: PersonRole = .coParent
        var roleOther: String = ""
    }

    @State private var drafts: [DraftPerson] = [DraftPerson()]

    var body: some View {
        OBScaffold {
            OBProgressRow(step: 4)
            OBSkipRow(action: onContinue)
            OBIconRing(system: "person.2")
            Text("Add people you'll reference")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 10)
            Text("Save your co-parent or kids now so you can reference them quickly later - no full contact info needed, just names.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            ForEach($drafts) { $draft in
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(FactTrailTheme.surface(for: colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Picker("Role", selection: $draft.role) {
                            ForEach(PersonRole.allCases) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(FactTrailTheme.secondaryText(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5))
                    }
                    if draft.role == .other {
                        TextField("Who are they? (e.g. grandparent, friend)", text: $draft.roleOther)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(FactTrailTheme.surface(for: colorScheme))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.bottom, 10)
            }

            Button {
                drafts.append(DraftPerson())
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text("Add another")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        } bottom: {
            OBPrimaryButton(title: "Continue") {
                savePeople()
                onContinue()
            }
        }
    }

    private func savePeople() {
        let people: [SavedPerson] = drafts.compactMap { draft in
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return SavedPerson(name: name, role: draft.role)
        }
        guard !people.isEmpty else { return }
        var existing = PeopleStore.load()
        existing.append(contentsOf: people)
        PeopleStore.save(existing)
    }
}
```

Note: the reference stores role only from the picker. The "Other" free-text is captured in the UI for parity but `SavedPerson` has no field for it, so only the role category is persisted. This matches the existing `SavedPerson` model and avoids changing it.

- [ ] **Step 2: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify on the simulator**

Relaunch onboarding and reach the People step. Verify:
- Progress segment 4 highlighted, Skip present.
- A name field plus a role menu (Co-parent, Child, Other). Choosing "Other" reveals the "Who are they?" field.
- "Add another" appends a row.
- Entering a name and tapping Continue finishes onboarding. Open the menu, then My people, and confirm the entered person appears with the chosen role.
- Skip and empty rows persist nothing.

- [ ] **Step 4: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/OnboardingFlow.swift"
git commit -m "Flesh out onboarding people step, wired to PeopleStore"
```

---

## Task 6: Account screen in the menu + profile row reflects the session

**Files:**
- Create: `coparent MPV/AccountView.swift`
- Modify: `coparent MPV/SettingsView.swift`

**Interfaces:**
- Consumes: `AccountManager` (Task 1) via `@Environment(AccountManager.self)`.
- Produces: `struct AccountView: View`.

- [ ] **Step 1: Create the Account screen**

Create `coparent MPV/AccountView.swift`:

```swift
import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSignOutConfirm = false
    @State private var showGoogleNote = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let session = account.session {
                    signedIn(session)
                } else {
                    signedOut
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func signedIn(_ session: AccountSession) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [FactTrailTheme.primaryAction(for: colorScheme), FactTrailTheme.aiAccent(for: colorScheme)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Text(initial(for: session))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                if let name = session.displayName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                }
                if let email = session.email, !email.isEmpty {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                Text("Signed in with Apple")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Button(role: .destructive) {
                showingSignOutConfirm = true
            } label: {
                Text("Sign out")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Sign out of Coparo?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { account.signOut() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your records stay on this device. You can sign in again anytime.")
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                )
            Text("Not signed in")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Sign in with Apple to attach your name to this device. Your records stay private either way.")
                .font(.system(size: 13.5))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                withAnimation { showGoogleNote = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle")
                        .font(.system(size: 17, weight: .medium))
                    Text("Continue with Google")
                        .font(.system(size: 14.5, weight: .semibold))
                }
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            if showGoogleNote {
                Text("Google sign-in is coming soon.")
                    .font(.system(size: 12))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 12)
    }

    private func initial(for session: AccountSession) -> String {
        let source = session.displayName?.isEmpty == false ? session.displayName! : (session.email ?? "?")
        return String(source.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Could not read the Apple credential. Please try again."
                return
            }
            account.applyAppleCredential(
                userID: credential.user,
                fullName: credential.fullName,
                email: credential.email
            )
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "Sign in with Apple didn't complete. Please try again."
        }
    }
}
```

- [ ] **Step 2: Point the SettingsView Account row at the new screen and reflect the session in the profile row**

In `coparent MPV/SettingsView.swift`, add an environment read to `SettingsView`. Just below the existing `@AppStorage("factTrailUserName") private var userName = ""` line (around line 94), add:

```swift
    @Environment(AccountManager.self) private var account
```

Replace the Account row (currently the `SettingsRow(systemImage: "person", label: "Account", destination: ComingSoonView(...))` block near line 123) with:

```swift
                        SettingsRow(systemImage: "person", label: "Account", destination: AccountView())
```

Replace the profile row's subtitle. In `profileRow` (around line 194), replace:

```swift
                Text("Stored on this device")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
```

with:

```swift
                Text(profileSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
```

And add this computed property to `SettingsView` (next to the existing `displayName`/`initial` helpers, around line 100):

```swift
    private var profileSubtitle: String {
        if let session = account.session {
            if let email = session.email, !email.isEmpty { return email }
            return "Signed in with Apple"
        }
        return "Stored on this device"
    }
```

Also update `displayName` so a signed-in name shows even when `factTrailUserName` is empty. Find the existing `displayName` computed property (it trims `userName`) and replace its body so it falls back to the session name:

```swift
    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let name = account.session?.displayName, !name.isEmpty { return name }
        return "You"
    }
```

Note: if the existing `displayName` returns a different default than `"You"`, keep that original default in the final `return` so the not-signed-in appearance is unchanged. Read the current implementation first and preserve its fallback string.

- [ ] **Step 3: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`. Because `SettingsView` is presented as a sheet from `ContentView`, and the environment is injected at the app root, `@Environment(AccountManager.self)` resolves in the sheet. If the build reports a missing environment at runtime rather than compile time, verify the app root injects `.environment(account)` (Task 2, Step 2).

- [ ] **Step 4: Verify on the simulator**

Launch the app (onboarding already complete). Open the menu:
- With no account: the profile row shows "Stored on this device", and the Account row opens a screen showing "Not signed in" with the Apple and Google buttons.
- Tapping the Google button shows "coming soon".
- On a physical device (or Apple-ID simulator): completing Apple sign-in updates the Account screen to show the name/email and "Signed in with Apple", the profile row subtitle changes, and Sign out (with confirm) returns it to "Not signed in".

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/AccountView.swift" "coparent MPV/SettingsView.swift"
git commit -m "Add Account screen and reflect the session in the menu profile row"
```

---

## Task 7: Home sign-in re-prompt banner

**Files:**
- Modify: `coparent MPV/ContentView.swift`

**Interfaces:**
- Consumes: `AccountManager` (Task 1); `AccountView` (Task 6).

- [ ] **Step 1: Read the home layout**

Open `coparent MPV/ContentView.swift` and locate the home screen's top-level content container (the `HomeView` body, or the top of the home `ScrollView`/`VStack` where the greeting and home cards render). Identify the outermost vertical stack so the banner can be inserted as the first child, above the existing content.

- [ ] **Step 2: Add the banner state and view**

In the view that renders the home content (the same type that shows the home cards), add these near its other state properties:

```swift
    @Environment(AccountManager.self) private var account
    @AppStorage("coparoHideSignInPrompt") private var hideSignInPrompt = false
    @State private var showingAccountFromBanner = false
```

Add this computed banner view to that type:

```swift
    @ViewBuilder
    private var signInBanner: some View {
        if !account.isSignedIn && !hideSignInPrompt {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to Coparo")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("Attach your name to this device with Apple.")
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                }
                Spacer(minLength: 8)
                Button {
                    showingAccountFromBanner = true
                } label: {
                    Text("Sign in")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(FactTrailTheme.primaryAction(for: colorScheme))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation { hideSignInPrompt = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(FactTrailTheme.aiSoftBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
```

If `colorScheme` is not already available in that type, add `@Environment(\.colorScheme) private var colorScheme`.

- [ ] **Step 3: Insert the banner and its presentation**

Insert `signInBanner` as the first element inside the home content stack (above the greeting/cards), with the same horizontal padding the home cards use. Then attach a sheet to that container so the "Sign in" button opens the Account screen:

```swift
        .sheet(isPresented: $showingAccountFromBanner) {
            NavigationStack { AccountView() }
        }
```

- [ ] **Step 4: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify on the simulator**

With no account, on the home screen:
- The banner appears at the top, styled with the soft accent background.
- Tapping "Sign in" opens the Account screen (with the Apple/Google buttons).
- Tapping the X dismisses the banner, and it stays gone after relaunch (until reset).
- When signed in (device), the banner does not appear.

- [ ] **Step 6: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/ContentView.swift"
git commit -m "Add dismissible home sign-in banner for unsigned users"
```

---

## Task 8: Reset integration

**Files:**
- Modify: `coparent MPV/ContentView.swift` (extend `resetAllData()`)

**Interfaces:**
- Consumes: `AccountStore` (Task 1).

- [ ] **Step 1: Locate `resetAllData()`**

In `coparent MPV/ContentView.swift`, find the `resetAllData()` function (it already clears the incident, check-in, exchange, document, entry, people, and custody stores).

- [ ] **Step 2: Also clear the account, onboarding, and banner flags**

Inside `resetAllData()`, after the existing store-clearing lines, add:

```swift
        // Account and first-run state so a reset returns to a true fresh install.
        AccountStore.clear()
        UserDefaults.standard.removeObject(forKey: "coparoHasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "coparoHideSignInPrompt")
```

If `resetAllData()` has access to the `AccountManager` (for example via `@Environment`), also set its `session = nil` so the live UI updates immediately; otherwise the `AccountStore.clear()` plus the onboarding relaunch covers it. To update the live manager, add `@Environment(AccountManager.self) private var account` to the enclosing type if not present, and add `account.signOut()` alongside the lines above (this both clears the store and updates the observable).

- [ ] **Step 3: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify on the simulator**

- Complete onboarding, dismiss the sign-in banner. Open the menu, Privacy & data, and run Reset all data.
- Relaunch the app. Verify it returns to the first-run splash and account screen, the banner-hidden state is cleared, and no account is present.

- [ ] **Step 5: Commit**

```bash
cd "/Users/mikehansen/Desktop/coparent MPV"
git add "coparent MPV/ContentView.swift"
git commit -m "Clear account and first-run flags on Reset all data"
```

---

## Final verification

- [ ] Reset to a fresh install, then walk the whole flow once: splash -> account -> (skip) -> welcome -> custody (add a schedule) -> mode (court) -> people (add one) -> complete -> home. Confirm the schedule colors the calendar, the mode badge and the person show in the menu, and the sign-in banner shows on home.
- [ ] On a physical device: complete Sign in with Apple from onboarding; confirm the name seeds the greeting and the Account screen; sign out; sign back in from the Account screen; confirm Reset all data returns to first-run.
```
