import SwiftUI

// MARK: - Models

/// A person the user saves to reference quickly (co-parent, a child, etc.). Names only —
/// no contact details — matching the app's "just names" stance.
struct SavedPerson: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var role: PersonRole
}

enum PersonRole: String, Codable, CaseIterable, Identifiable {
    case coParent = "Co-parent"
    case child = "Child"
    case other = "Other"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .coParent: return "person"
        case .child: return "figure.child"
        case .other: return "person.crop.circle"
        }
    }
}

enum PeopleStore {
    static let key = "coparoPeople"

    static func load() -> [SavedPerson] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedPerson].self, from: data)) ?? []
    }

    static func save(_ people: [SavedPerson]) {
        if let data = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// How the app should prepare records. Mirrors the onboarding "Mode" choice.
enum CoparoMode: String, CaseIterable, Identifiable {
    case casual
    case court

    var id: String { rawValue }

    var badge: String {
        switch self {
        case .casual: return "Casual"
        case .court: return "Court"
        }
    }

    var title: String {
        switch self {
        case .casual: return "Just keeping a record"
        case .court: return "Court-ready records"
        }
    }

    var summary: String {
        switch self {
        case .casual:
            return "Log things as they happen, just in case you need them later."
        case .court:
            return "Coparo prepares neutral, lawyer-ready summaries of your entries so they're ready if you ever need them."
        }
    }

    var systemImage: String {
        switch self {
        case .casual: return "heart"
        case .court: return "building.columns"
        }
    }
}

// MARK: - Settings sheet

/// The app's main menu, presented as a bottom sheet from the home hamburger. Matches the
/// reference's grouped sections. Preferences (name, people, mode, appearance) are stored
/// locally; the data actions (export / restore / reset) are handled by ContentView.
struct SettingsView: View {
    let onExport: () -> Void
    let onRestore: () -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountManager.self) private var account
    @AppStorage("factTrailUserName") private var userName = ""
    @AppStorage("factTrailAppearance") private var appearanceRaw = FactTrailAppearance.light.rawValue
    @AppStorage("coparoMode") private var modeRaw = CoparoMode.casual.rawValue

    private var mode: CoparoMode { CoparoMode(rawValue: modeRaw) ?? .casual }
    private var appearance: FactTrailAppearance { FactTrailAppearance(rawValue: appearanceRaw) ?? .light }

    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let name = account.session?.displayName, !name.isEmpty { return name }
        return "You"
    }

    private var profileSubtitle: String {
        if let session = account.session {
            if let email = session.email, !email.isEmpty { return email }
            return "Signed in with Apple"
        }
        return "Stored on this device"
    }

    private var initial: String {
        displayName.first.map { String($0).uppercased() } ?? "Y"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    profileRow
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 16)

                    fullDivider

                    menuSection {
                        SettingsRow(systemImage: "person.2", label: "My people", destination: MyPeopleView())
                        SettingsRow(systemImage: "person", label: "Account", destination: AccountView())
                    }

                    fullDivider

                    menuSection {
                        SettingsRow(systemImage: "calendar", label: "Custody schedule", destination: CustodyDescribeView(userName: userName))
                        SettingsRow(systemImage: "shield", label: "Mode", trailing: .badge(mode.badge), destination: ModeView())
                        SettingsRow(systemImage: "bell", label: "Notifications", destination: ComingSoonView(
                            systemImage: "bell",
                            title: "Notifications",
                            message: "Gentle reminders to finish a thin entry or log an exchange, on your schedule. Coming soon."
                        ))
                        SettingsRow(systemImage: "sun.max", label: "Appearance", trailing: .value(appearance.rawValue), destination: AppearanceView())
                    }

                    fullDivider

                    menuSection {
                        SettingsRow(systemImage: "mic", label: "Privacy & data", destination: PrivacyDataView(onRestore: onRestore, onReset: onReset))
                        Button {
                            onExport()
                        } label: {
                            SettingsRowLabel(systemImage: "tray.and.arrow.down", label: "Export all data", trailing: .chevron)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
            .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var profileRow: some View {
        HStack(spacing: 12) {
            Text(initial)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [FactTrailTheme.primaryAction(for: colorScheme), FactTrailTheme.aiAccent(for: colorScheme)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Text(profileSubtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }

            Spacer()
        }
    }

    /// A group of full-width rows. Matches the reference's flush list (no card outline);
    /// groups are separated by full-width dividers rather than boxed in.
    private func menuSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(.vertical, 6)
    }

    private var fullDivider: some View {
        Rectangle()
            .fill(FactTrailTheme.border(for: colorScheme))
            .frame(height: 1)
    }
}

// MARK: - Reusable rows

enum SettingsRowTrailing {
    case chevron
    case badge(String)
    case value(String)
}

/// A tappable settings row that pushes a destination.
private struct SettingsRow<Destination: View>: View {
    let systemImage: String
    let label: String
    var trailing: SettingsRowTrailing = .chevron
    let destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            SettingsRowLabel(systemImage: systemImage, label: label, trailing: trailing)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRowLabel: View {
    let systemImage: String
    let label: String
    var trailing: SettingsRowTrailing = .chevron
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            .frame(width: 32, height: 32)

            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Spacer()

            switch trailing {
            case .chevron:
                chevron
            case .badge(let text):
                Text(text)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12)))
            case .value(let text):
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                chevron
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
    }
}

// MARK: - My people

private struct MyPeopleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("factTrailUserName") private var userName = ""
    @State private var people: [SavedPerson] = []
    @State private var draftName = ""
    @State private var draftRole: PersonRole = .coParent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save your co-parent or kids so you can reference them quickly later — just names, no contact info.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                labeledField("What should the app call you?") {
                    TextField("Your name", text: $userName)
                        .textFieldStyle(.plain)
                        .fieldChrome(colorScheme)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("People you'll reference")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

                    if people.isEmpty {
                        Text("No one added yet.")
                            .font(.system(size: 14))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(people) { person in
                            HStack(spacing: 12) {
                                Image(systemName: person.role.systemImage)
                                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                    Text(person.role.rawValue)
                                        .font(.system(size: 12))
                                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                                }
                                Spacer()
                                Button {
                                    remove(person)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add someone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .fieldChrome(colorScheme)
                    Picker("Role", selection: $draftRole) {
                        ForEach(PersonRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        addDraft()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailPrimaryButtonStyle())
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("My people")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { people = PeopleStore.load() }
    }

    private func addDraft() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        people.append(SavedPerson(name: name, role: draftRole))
        PeopleStore.save(people)
        draftName = ""
    }

    private func remove(_ person: SavedPerson) {
        people.removeAll { $0.id == person.id }
        PeopleStore.save(people)
    }

    private func labeledField<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            content()
        }
    }
}

// MARK: - Mode

private struct ModeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("coparoMode") private var modeRaw = CoparoMode.casual.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How should we prepare your records? This controls what happens quietly in the background. You can change it anytime.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                ForEach(CoparoMode.allCases) { option in
                    let isSelected = modeRaw == option.rawValue
                    Button {
                        modeRaw = option.rawValue
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: option.systemImage)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                Text(option.summary)
                                    .font(.system(size: 13))
                                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Mode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance

private struct AppearanceView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("factTrailAppearance") private var appearanceRaw = FactTrailAppearance.light.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose how Coparo looks.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                ForEach(FactTrailAppearance.allCases) { option in
                    let isSelected = appearanceRaw == option.rawValue
                    Button {
                        appearanceRaw = option.rawValue
                    } label: {
                        HStack {
                            Image(systemName: option == .dark ? "moon.stars" : "sun.max")
                                .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
                                .frame(width: 28)
                            Text(option.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Privacy & data

private struct PrivacyDataView: View {
    let onRestore: () -> Void
    let onReset: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your records stay on this device. From here you can restore a backup or clear everything.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: "faceid")
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("App lock")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Text("Require Face ID to open — coming soon")
                                .font(.system(size: 12))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        Spacer()
                    }
                    .padding(14)
                }
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }

                Button {
                    onRestore()
                } label: {
                    Label("Restore from backup", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())

                Button(role: .destructive) {
                    onReset()
                } label: {
                    Label("Reset all data", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Privacy & data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Coming soon placeholder

private struct ComingSoonView: View {
    let systemImage: String
    let title: String
    let message: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            Text("Coming soon")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                .padding(.vertical, 5)
                .padding(.horizontal, 12)
                .background(Capsule().fill(FactTrailTheme.aiSoftBackground(for: colorScheme)))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func fieldChrome(_ colorScheme: ColorScheme) -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
    }
}
