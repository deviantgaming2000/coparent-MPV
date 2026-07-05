# Onboarding, Sign-in, and Accounts - Design

Date: 2026-07-04
Status: Approved, ready for implementation plan

## Goal

Recreate the reference app's first-run onboarding as a native SwiftUI flow, matching its look step for step.
The flow starts with a splash, then an account screen where the user signs in with Apple (fully working) or Google (present but "coming soon"), or skips.
It continues through a short wizard that sets up custody schedule, mode, and people, then lands in the app.
The signed-in account surfaces in the menu profile row and a real Account screen.

## Context and constraints

- The app is local-first today.
  All data lives on the device in JSON files and UserDefaults, and there is no backend.
- Because there is no backend, an account is a **local identity**.
  Sign in with Apple captures a stable user id plus name and email and displays them, but nothing syncs server-side yet.
- Email/password account creation and email verification require a backend, so they are **dropped** from this build.
  The reference's account screen keeps only the two SSO buttons plus a skip.
- The app entry point (`coparent_MPVApp.swift`) shows `ContentView()` directly with no onboarding.
- The project already has a development team (`N4D8948SYX`), automatic signing, and an empty entitlements file at `coparent MPV/coparent_MPV.entitlements`.
- The custody, mode, and people steps write to stores the app already has (`CustodyScheduleStore`, the `coparoMode` app setting, `PeopleStore`), so the wizard reuses existing features rather than duplicating them.

## Reference theme (match exactly)

Light mode values from the reference `:root`:

- `--bg: #F7F4EF`, `--surface: #FFFFFF`
- `--text-primary: #172033`, `--text-secondary: #4B5563`, `--text-muted: #6B7280`
- `--border: #E5E1DA`, `--primary: #2F5D8C`, `--accent: #4F8F8B`
- Splash gradient: `linear-gradient(160deg, #2F5D8C 0%, #3d7a8c 55%, #4F8F8B 100%)`
- Account header banner gradient: `linear-gradient(160deg, #2F5D8C 0%, #4F8F8B 100%)`, 220px tall, bottom corners rounded 32px
- Primary button gradient: `linear-gradient(135deg, primary, mix(primary 75%, accent))`

These already correspond to `FactTrailTheme`, which is the source of truth in code.
Dark mode uses the existing `FactTrailTheme` dark tokens.

## Scope decisions

- **Full onboarding wizard**, matching the reference screen for screen.
- **Apple + Google only** on the account screen.
  Apple works; Google is present but shows a "coming soon" note when tapped; no email/password fields.
- The **verify-email** screen is dropped, since it only existed for the email path.
- The custody step opens the **existing** `CustodyScheduleView` for "Yes, let's add it".
  The reference's natural-language "describe your schedule" with AI mapping is **out of scope** for this pass (it is mocked even in the reference).
- Sign-in is optional.
  The account screen has a "Skip for now" that continues into the wizard as a local unsigned user.

## Screens

The flow is a horizontal slide sequence, each screen sliding in from the right, matching the reference transitions.

### 1. Splash

- Full-bleed splash gradient, centered "book with heart" mark in a translucent rounded square, "Coparo" wordmark, tagline "A clear record, quietly kept.", three dots near the bottom.
- Auto-advances to the account screen after about 2.7 seconds.
  A tap also advances.

### 2. Account

- Teal header banner (220px, rounded bottom) with a heart icon ring, title "Glad you're here.\nLet's get you set up.", subtitle "Your records stay private and secure."
- A white card overlapping the banner containing:
  - **Continue with Apple**: black button with the Apple glyph.
    Uses the native Sign in with Apple flow.
  - **Continue with Google**: white bordered button with the Google glyph.
    Tapping shows a small "Google sign-in is coming soon" note.
    It does not start a flow.
  - **Skip for now**: a muted text button beneath the buttons.
    This is the one intentional addition over the reference, to satisfy the optional-sign-in requirement.
    It matches the reference's muted skip styling.
  - Legal note: "By continuing, you agree to our Terms and Privacy Policy." with tappable links (links can point to placeholders for now).
- On successful Apple sign-in: persist the session, and if a name was returned and `factTrailUserName` is empty, populate it.
  Then advance to Welcome.
- On skip: no session, advance to Welcome.

### 3. Welcome

- Heart icon ring, title "Welcome, [name]." when a name is known, otherwise "Welcome to Coparo."
- Subtitle "Just a few questions before we get started - each one takes a few seconds, and you can skip anything you're not ready for."
- Primary button "Let's go" advances to the custody step.

### 4. Custody schedule

- Progress row of four segments with the first done and the second current.
- A "Skip" link top-right that advances to Mode.
- Calendar icon ring, title "Add your custody schedule?", subtitle about color-coding the calendar.
- Two choice rows: "Yes, let's add it" and "Not right now".
- "Yes, let's add it" opens the existing `CustodyScheduleView`.
  Saving there writes to `CustodyScheduleStore` and returns to the wizard, advancing to Mode.
- "Not right now" advances to Mode without changes.

### 5. Mode

- Progress row with the first two done and the third current.
- A "Skip" link that advances to People.
- Shield icon ring, title "How should we prepare your records?", subtitle about background behavior.
- Two choice rows: "Just keeping a record" (casual) and "I want my records court-ready" (court).
- Selecting a choice sets the `coparoMode` app setting.
- "Continue" advances to People.

### 6. People

- Progress row with the first three done and the fourth current.
- A "Skip" link that advances to Complete.
- People icon ring, title "Add people you'll reference", subtitle about saving names only.
- One or more rows, each a name field plus a role picker (Co-parent, Child, Other).
  Choosing "Other" reveals a "Who are they?" field.
- "Add another" appends a row.
- "Continue" saves the non-empty rows to `PeopleStore` and advances to Complete.

### 7. Complete

- Animated check icon, title "You're all set.", subtitle "Your record starts now...".
- "Go to Coparo" finishes onboarding: set `coparoHasCompletedOnboarding = true` and dismiss the flow into `ContentView`.

## Components

### Account model and store (`AccountSession.swift`, new)

- `AccountProvider`: enum with `.apple` and `.google`.
- `AccountSession`: `Codable` struct with `provider`, stable `userID`, optional `displayName`, optional `email`, `signedInAt`.
- `AccountStore`: persists one session to UserDefaults under `coparoAccountSession`, with `load()`, `save(_:)`, `clear()`.
- `AccountManager`: an `@Observable` final class holding the current `session`, exposing `applyAppleCredential(userID:fullName:email:)`, `signOut()`, `isSignedIn`, and display helpers.
  Created once in `coparent_MPVApp` and shared with the onboarding flow, `ContentView`, and `SettingsView`.

### Sign in with Apple

- Native `SignInWithAppleButton` from `AuthenticationServices`, no third-party SDK.
- On success, read the stable `user` id plus `fullName` and `email` (Apple sends name and email only on first authorization, so persist when present).
- Add `com.apple.developer.applesignin` (value `["Default"]`) to `coparent_MPV.entitlements`.

### Onboarding container (`OnboardingFlow.swift`, new)

- An `OnboardingContainerView` owns the current step and renders the seven screens with slide transitions.
- Root gate: `@AppStorage("coparoHasCompletedOnboarding")`.
  When false, the app shows `OnboardingContainerView`; when true, it shows `ContentView`.
  The gate lives at the app root so onboarding sits above the whole app.
- Each screen is a focused subview (`OnboardingSplash`, `OnboardingAccount`, `OnboardingWelcome`, `OnboardingCustodyStep`, `OnboardingModeStep`, `OnboardingPeopleStep`, `OnboardingComplete`).

### Menu profile row and Account section

- The `SettingsView` profile row shows the account name and email and "Signed in with Apple" when signed in, and "Stored on this device" when not.
- The Account row opens a new `AccountView`:
  - Signed in: name, email, "Signed in with Apple", and a **Sign out** button with confirmation.
  - Not signed in: "Not signed in", a short explanation, a Sign in with Apple button, and the coming-soon Google option.

### Re-prompt nudge

- On Home, when there is no account, show a small dismissible banner inviting sign-in.
  Tapping opens sign-in.
  Dismissing sets `@AppStorage("coparoHideSignInPrompt")` so it stays hidden.

### Reset integration

- Extend "Reset all data" to also clear the account session, `coparoHasCompletedOnboarding`, and `coparoHideSignInPrompt`, returning the app to a true fresh first-launch.

## Data flow

1. First launch: `coparoHasCompletedOnboarding` is false, so the splash plays and slides to the account screen.
2. Apple sign-in builds and saves an `AccountSession`, optionally seeds `factTrailUserName`, and advances through the wizard.
   Skip advances without a session.
3. Custody, mode, and people steps write to their existing stores when the user provides input, and are individually skippable.
4. Complete sets `coparoHasCompletedOnboarding = true` and enters `ContentView`.
5. In the menu, the Account screen reflects the state and lets the user sign in or sign out.
   Sign out clears the session but leaves onboarding complete.

## Error handling

- If Sign in with Apple fails, stay on the account screen and show a brief, non-blocking message.
  Cancellation is silent.
- The Google button is inert, so it cannot start a failing flow.
- If the capability is missing at runtime, the button surfaces the system error without crashing.

## Testing

- Sign in with Apple runs on the simulator only when it is signed into an Apple ID in Settings, otherwise it is verified on a physical device.
- Verify: first launch plays the splash and shows the account screen; Apple sign-in advances and seeds the name; skip advances as unsigned; each wizard step is skippable; custody "Yes" opens the existing setup and saves; mode and people persist; complete enters the app; the menu shows the account; sign-out returns to unsigned; the Home banner appears when unsigned and hides when dismissed; reset returns to first-launch onboarding.
- Google remains inert until a Google Cloud OAuth iOS client id is created and wired.

## Out of scope for this pass

- Any backend, server-side account, or cross-device sync.
- Email/password account creation and email verification.
- Real Google sign-in (deferred until a client id exists).
- Natural-language "describe your schedule" with AI mapping in the custody step.
- Requiring sign-in to use the app.
