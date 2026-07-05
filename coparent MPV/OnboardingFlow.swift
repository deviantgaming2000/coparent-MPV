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
