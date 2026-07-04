import SwiftUI

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

enum FactTrailAppearance: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

enum FactTrailTheme {
    static let accent = Color(hex: 0x2F5D8C)
    static let secondaryAccent = Color(hex: 0x4F8F8B)
    static let coolAccent = Color(hex: 0xEAF2F8)

    static func background(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x101820) : Color(hex: 0xF7F4EF)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x17212B) : Color(hex: 0xFFFFFF)
    }

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xF4F1EA) : Color(hex: 0x172033)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0xC8CED6) : Color(hex: 0x4B5563)
    }

    static func mutedText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x8F9BA8) : Color(hex: 0x6B7280)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x2B3947) : Color(hex: 0xE5E1DA)
    }

    static func primaryAction(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x6FA3D2) : Color(hex: 0x2F5D8C)
    }

    static func aiAccent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x72B7B2) : Color(hex: 0x4F8F8B)
    }

    static func aiSoftBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: 0x18363A) : Color(hex: 0xEAF2F8)
    }

    static func primaryForeground(for colorScheme: ColorScheme) -> Color {
        .white
    }

    // Prototype primary button: linear-gradient(135deg, primary, mix(primary 75%, accent)).
    static func primaryButtonColors(for colorScheme: ColorScheme) -> [Color] {
        colorScheme == .dark
            ? [Color(hex: 0x6FA3D2), Color(hex: 0x6FA8CA)]
            : [Color(hex: 0x2F5D8C), Color(hex: 0x37699C)]
    }

    // Prototype check-in CTA: linear-gradient(135deg, accent, mix(accent 75%, primary)).
    static func checkInButtonColors(for colorScheme: ColorScheme) -> [Color] {
        colorScheme == .dark
            ? [Color(hex: 0x72B7B2), Color(hex: 0x71B2BA)]
            : [Color(hex: 0x4F8F8B), Color(hex: 0x47838B)]
    }

    // Kept for the gradient splash / onboarding header, which stay gradient in the prototype.
    static func backgroundColors(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            return [background(for: colorScheme), Color(hex: 0x111D27), background(for: colorScheme)]
        case .light:
            return [background(for: colorScheme), Color(hex: 0xEFEAE2), background(for: colorScheme)]
        @unknown default:
            return [Color(.systemBackground)]
        }
    }
}

// Flat, static screen background — matches the prototype's solid `--bg` fill.
struct FactTrailBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FactTrailTheme.background(for: colorScheme)
            .ignoresSafeArea()
    }
}

// Prototype `.btn-save-primary` / `.ob-primary-btn`:
// gradient fill, radius 14, white 15/semibold, single soft shadow, press-scale 0.98.
struct FactTrailPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FactTrailTheme.primaryForeground(for: colorScheme))
            .padding(.vertical, 15)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: FactTrailTheme.primaryButtonColors(for: colorScheme),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: FactTrailTheme.primaryAction(for: colorScheme).opacity(configuration.isPressed ? 0.14 : 0.28),
                        radius: 7,
                        y: 4
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

// Prototype `.checkin-cta`: teal gradient, radius 14, white 15/semibold, single soft shadow.
struct FactTrailCheckInButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: FactTrailTheme.checkInButtonColors(for: colorScheme),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: FactTrailTheme.aiAccent(for: colorScheme).opacity(configuration.isPressed ? 0.14 : 0.28),
                        radius: 7,
                        y: 4
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

// Prototype secondary / outline button (`.attach-btn`, `.back-btn` family):
// solid surface, 1px hairline border, primary-colored text, whisper shadow.
struct FactTrailGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FactTrailTheme.surface(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

struct FactTrailGlassCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

extension View {
    func factTrailScreenBackground() -> some View {
        background(FactTrailBackground())
    }

    func factTrailFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(FactTrailBackground())
    }

    func factTrailGlassCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(FactTrailGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// Prototype card: solid `--surface`, 1px `--border` hairline, box-shadow 0 2px 8px rgba(0,0,0,0.06).
private struct FactTrailGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(FactTrailTheme.surface(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 4, x: 0, y: 2)
            }
    }
}
