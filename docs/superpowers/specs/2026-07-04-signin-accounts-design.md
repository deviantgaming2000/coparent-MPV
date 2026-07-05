# Sign-in and Accounts - Design

Date: 2026-07-04
Status: Approved, ready for implementation plan

## Goal

Let a user establish an account when they first open Coparo, using Sign in with Apple (fully working) or Google (button present but deferred).
The user can skip sign-in and use the app as a local, unsigned user.
The signed-in account is shown in the Account section of the menu, and the app can gently re-prompt a skipped user to sign in later.

## Context and constraints

- The app is local-first today.
  All data lives on the device in JSON files and UserDefaults, and there is no backend.
- Because there is no backend, an account is a **local identity** for now.
  It captures the user's name and email and displays them, but it does not sync or protect data server-side yet.
  This matches the intent that sign-in is optional now and may become required later.
- The app entry point (`coparent_MPVApp.swift`) currently shows `ContentView()` directly with no onboarding.
- The project already has a development team (`N4D8948SYX`), automatic signing, and an (empty) entitlements file at `coparent MPV/coparent_MPV.entitlements`.
- Apple's App Store rules require that offering a third-party sign-in (Google) also offer Sign in with Apple, so the two belong together.

## Scope decisions

- **Apple now, Google button ready.**
  Build Sign in with Apple fully.
  Add the Google button to the UI as a clearly-labeled "Coming soon" disabled control until a Google Cloud OAuth iOS client ID exists.
- **Skip enters the app, with re-prompt.**
  Skipping enters the app as a local unsigned user.
  A dismissible banner on Home can invite the user to sign in later.

## Components

### 1. Account model and store (`AccountSession.swift`, new)

- `AccountProvider`: enum with `.apple` and `.google`.
- `AccountSession`: `Codable` struct holding `provider`, a stable `userID`, optional `displayName`, optional `email`, and `signedInAt`.
- `AccountStore`: persists a single session to UserDefaults under key `coparoAccountSession`, with `load()`, `save(_:)`, and `clear()`.
- `AccountManager`: an `@Observable` final class that holds the current `session` and exposes:
  - `applyAppleCredential(userID:fullName:email:)` to create and persist a session from an Apple credential.
  - `signOut()` to clear the session.
  - A convenience `isSignedIn` and a display helper for name/email.
  - Created once in `coparent_MPVApp` and shared with `ContentView` and `SettingsView`.

### 2. Sign in with Apple (native)

- Use Apple's native `SignInWithAppleButton` from `AuthenticationServices`.
  No third-party SDK.
- On success, read the stable `user` identifier plus `fullName` and `email`.
  Apple only returns name and email on the first authorization for a given Apple ID, so persist them when present and keep them locally afterward.
- Add the `com.apple.developer.applesignin` entitlement (value `["Default"]`) to `coparent_MPV.entitlements`.
- If a name is returned and the existing `factTrailUserName` is empty, populate it so the greeting and profile row reflect the real name.

### 3. Onboarding (`OnboardingView.swift`, new)

- Add a first-launch gate: `@AppStorage("coparoHasCompletedOnboarding")`.
  When false, the app shows the welcome screen before `ContentView`.
- The welcome screen shows the Coparo name and mark, a one-line tagline, and three actions:
  - **Sign in with Apple** (working).
  - **Continue with Google** (visible, disabled, labeled "Coming soon").
  - **Skip for now** (text button).
- A successful sign-in or a skip sets `coparoHasCompletedOnboarding = true` and enters the app.
- The gate lives at the root (in `coparent_MPVApp` or a thin wrapper) so onboarding is shown above the whole app.

### 4. Account section (`AccountView.swift`, new; replaces the Account "coming soon" row)

- When signed in: show the initial or name, the email, "Signed in with Apple", and a **Sign out** button with a confirmation.
- When not signed in: show "Not signed in", a short explanation, a Sign in with Apple button, and the coming-soon Google option.
- The `SettingsView` profile row reflects the state: email or "Signed in with Apple" when signed in, "Stored on this device" when not.

### 5. Re-prompt nudge

- On Home, when there is no account, show a small dismissible banner inviting sign-in.
  Tapping it opens the sign-in path.
  Dismissing it sets `@AppStorage("coparoHideSignInPrompt")` so it stays hidden.

### 6. Reset integration

- Extend the existing "Reset all data" action to also clear the account session, the `coparoHasCompletedOnboarding` flag, and the `coparoHideSignInPrompt` flag.
- After a reset the app returns to a true fresh first-launch state, matching the App Store goal that nothing is baked in.

## Data flow

1. First launch: `coparoHasCompletedOnboarding` is false, so `OnboardingView` is shown.
2. User taps Sign in with Apple.
   The system returns an Apple credential.
   `AccountManager.applyAppleCredential(...)` builds an `AccountSession`, `AccountStore` saves it, and if a name was provided and `factTrailUserName` is empty it is populated.
   `coparoHasCompletedOnboarding` is set true and the app enters `ContentView`.
3. Or the user taps Skip.
   No session is created, `coparoHasCompletedOnboarding` is set true, and the app enters `ContentView` as a local unsigned user.
4. In the menu, the Account row shows the current state and lets the user sign in or sign out.
5. Sign out clears the session but leaves onboarding complete, so the user stays in the app as a local unsigned user and can be re-prompted.

## Error handling

- If Sign in with Apple fails or is cancelled, stay on the current screen and show a brief, non-blocking message.
  Cancellation is silent.
- If the entitlement or capability is missing at runtime (for example on a build without the capability), the button surfaces the system error without crashing.
- The Google button is disabled, so it cannot start a flow that would fail.

## Testing

- Sign in with Apple runs on the simulator only when the simulator is signed into an Apple ID in the Settings app.
  Otherwise it is verified on a physical device.
- Verify: first-launch shows onboarding; skip enters the app and Account shows "Not signed in"; sign-in populates Account and the profile row; sign-out returns to the unsigned state; the Home banner appears when unsigned and hides when dismissed; reset returns to first-launch onboarding.
- Google remains inert until a Google Cloud OAuth iOS client ID is created and wired.

## Out of scope for this pass

- Any backend, server-side account, or cross-device sync.
- Real Google sign-in (deferred until a client ID exists).
- Requiring sign-in to use the app.
- Account deletion beyond local sign-out and reset.
