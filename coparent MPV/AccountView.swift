import SwiftUI

enum EmailAuthMode: Identifiable {
    case create
    case login
    var id: Int { self == .create ? 0 : 1 }
}

struct AccountView: View {
    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSignOutConfirm = false
    @State private var authMode: EmailAuthMode?

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
        .sheet(item: $authMode) { mode in
            EmailAuthSheet(mode: mode)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
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
                Text("Signed in on this device")
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
            Text("Set up your account")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("An account keeps your profile on this device and is ready for future features. Your records stay private either way.")
                .font(.system(size: 13.5))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                authMode = .create
            } label: {
                Text("Create an account")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())

            Button {
                authMode = .login
            } label: {
                Text("Already have an account? Log in")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    private func initial(for session: AccountSession) -> String {
        let source = session.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? session.email ?? "?"
        return String(source.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

/// The create-account / log-in form. Local only — no backend, no email verification.
struct EmailAuthSheet: View {
    let mode: EmailAuthMode

    @Environment(AccountManager.self) private var account
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var currentMode: EmailAuthMode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?

    init(mode: EmailAuthMode) {
        self.mode = mode
        _currentMode = State(initialValue: mode)
    }

    private var isCreate: Bool { currentMode == .create }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isCreate ? "Create an account" : "Log in")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                if isCreate {
                    field("Name (optional)", text: $name, keyboard: .default, secure: false, autocap: .words)
                }
                field("Email", text: $email, keyboard: .emailAddress, secure: false, autocap: .never)
                field(isCreate ? "Password (min 6 characters)" : "Password", text: $password, keyboard: .default, secure: true, autocap: .never)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: submit) {
                    Text(isCreate ? "Create account" : "Log in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailPrimaryButtonStyle())

                Button {
                    errorMessage = nil
                    currentMode = isCreate ? .login : .create
                } label: {
                    Text(isCreate ? "Already have an account? Log in" : "Need an account? Create one")
                        .font(.system(size: 13.5, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Text("Your account and records stay on this device. We don't verify the email or store a password on any server.")
                    .font(.system(size: 11.5, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(22)
        }
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType, secure: Bool, autocap: TextInputAutocapitalization) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocap)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 16, weight: .regular, design: .default))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FactTrailTheme.background(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
        }
    }

    private func submit() {
        errorMessage = nil
        do {
            if isCreate {
                try account.createEmailAccount(email: email, password: password, displayName: name)
            } else {
                try account.signInWithEmail(email: email, password: password)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
