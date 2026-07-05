import SwiftUI
import AuthenticationServices

struct AccountView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSignOutConfirm = false
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
