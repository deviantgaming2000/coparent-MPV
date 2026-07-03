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
        switch colorScheme {
        case .dark:
            return .white
        case .light:
            return .white
        @unknown default:
            return .white
        }
    }

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

    static func glassOverlayColors(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            return [surface(for: colorScheme).opacity(0.86), .white.opacity(0.035), aiSoftBackground(for: colorScheme).opacity(0.28)]
        case .light:
            return [surface(for: colorScheme).opacity(0.96), .white.opacity(0.58), aiSoftBackground(for: colorScheme).opacity(0.32)]
        @unknown default:
            return [.white.opacity(0.20)]
        }
    }

    static func glassStrokeColors(for colorScheme: ColorScheme) -> [Color] {
        switch colorScheme {
        case .dark:
            return [border(for: colorScheme).opacity(0.95), primaryAction(for: colorScheme).opacity(0.28), .white.opacity(0.05)]
        case .light:
            return [border(for: colorScheme), primaryAction(for: colorScheme).opacity(0.18), .black.opacity(0.04)]
        @unknown default:
            return [.white.opacity(0.35)]
        }
    }
}

struct FactTrailBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 0.34

            ZStack {
                LinearGradient(
                    colors: FactTrailTheme.backgroundColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if colorScheme == .dark {
                    FactTrailInkClouds(phase: phase, colorScheme: colorScheme)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct FactTrailInkClouds: View {
    var phase: CGFloat
    var colorScheme: ColorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    FactTrailInkBlob(colors: colors(for: index))
                        .frame(width: size(for: index).width, height: size(for: index).height)
                        .blur(radius: blur(for: index))
                        .opacity(opacity(for: index))
                        .rotationEffect(.radians(Double(phase * rotationSpeed(for: index) + CGFloat(index) * 0.71)))
                        .scaleEffect(scale(for: index))
                        .position(position(in: proxy.size, for: index))
                }

                ForEach(0..<5, id: \.self) { index in
                    FactTrailWispyRibbon(
                        phase: phase * (index.isMultiple(of: 2) ? 1.0 : -1.0) + CGFloat(index) * 0.82,
                        amplitude: 36 + CGFloat(index * 8),
                        baseline: 0.18 + CGFloat(index) * 0.16,
                        frequency: 0.82 + CGFloat(index) * 0.12
                    )
                    .stroke(
                        LinearGradient(
                            colors: ribbonColors(for: index),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 58 + CGFloat(index * 12), lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 24 + CGFloat(index * 4))
                    .opacity(0.34)
                }
            }
        }
    }

    private func position(in size: CGSize, for index: Int) -> CGPoint {
        let baseX = [0.12, 0.38, 0.78, 0.26, 0.64, 0.92, 0.48, 0.06][index]
        let baseY = [0.16, 0.28, 0.22, 0.52, 0.62, 0.78, 0.88, 0.70][index]
        let xTravel = cos(phase * (0.62 + CGFloat(index) * 0.035) + CGFloat(index) * 1.13) * size.width * 0.24
        let yTravel = sin(phase * (0.48 + CGFloat(index) * 0.030) + CGFloat(index) * 0.91) * size.height * 0.11

        return CGPoint(
            x: size.width * baseX + xTravel,
            y: size.height * baseY + yTravel
        )
    }

    private func size(for index: Int) -> CGSize {
        let sizes = [
            CGSize(width: 360, height: 260),
            CGSize(width: 420, height: 300),
            CGSize(width: 330, height: 430),
            CGSize(width: 460, height: 260),
            CGSize(width: 390, height: 350),
            CGSize(width: 300, height: 240),
            CGSize(width: 520, height: 220),
            CGSize(width: 280, height: 380)
        ]
        return sizes[index]
    }

    private func colors(for index: Int) -> [Color] {
        switch index % 4 {
        case 0:
            return [
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.26),
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.20),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.16),
                .clear
            ]
        case 1:
            return [
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.24),
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.18),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.14),
                .clear
            ]
        case 2:
            return [
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.22),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.16),
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.18),
                .clear
            ]
        default:
            return [
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.22),
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.18),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.13),
                .clear
            ]
        }
    }

    private func opacity(for index: Int) -> Double {
        [0.34, 0.30, 0.28, 0.24, 0.32, 0.25, 0.22, 0.27][index]
    }

    private func blur(for index: Int) -> CGFloat {
        [42, 54, 48, 58, 52, 44, 64, 50][index]
    }

    private func rotationSpeed(for index: Int) -> CGFloat {
        [0.18, -0.16, 0.14, -0.20, 0.12, -0.18, 0.10, -0.15][index]
    }

    private func scale(for index: Int) -> CGFloat {
        1 + sin(phase * (0.72 + CGFloat(index) * 0.04) + CGFloat(index)) * 0.08
    }

    private func ribbonColors(for index: Int) -> [Color] {
        if index.isMultiple(of: 3) {
            return [
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.32),
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.26),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.14),
                .clear
            ]
        }

        if index.isMultiple(of: 2) {
            return [
                .clear,
                FactTrailTheme.primaryAction(for: colorScheme).opacity(0.26),
                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.28),
                FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.13)
            ]
        }

        return [
            FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.14),
            FactTrailTheme.aiAccent(for: colorScheme).opacity(0.30),
            FactTrailTheme.primaryAction(for: colorScheme).opacity(0.24),
            .clear
        ]
    }
}

private struct FactTrailInkBlob: View {
    let colors: [Color]

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 6,
                    endRadius: 190
                )
            )
    }
}

private struct FactTrailWispyRibbon: Shape {
    var phase: CGFloat
    var amplitude: CGFloat
    var baseline: CGFloat
    var frequency: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.height * baseline
        let width = max(rect.width, 1)
        let extendedWidth = width * 1.36
        let startX = -width * 0.18
        let endX = width * 1.18

        path.move(to: CGPoint(x: startX, y: baseY))

        for x in stride(from: startX, through: endX, by: 12) {
            let progress = (x - startX) / extendedWidth
            let y = baseY
                + sin(progress * .pi * 2.0 * frequency + phase) * amplitude
                + sin(progress * .pi * 4.0 * frequency - phase * 2.0) * amplitude * 0.22
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

struct FactTrailPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(FactTrailTheme.primaryForeground(for: colorScheme))
            .padding(.vertical, 15)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FactTrailTheme.primaryAction(for: colorScheme),
                                FactTrailTheme.aiAccent(for: colorScheme)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.30), .white.opacity(0.10), .black.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.65
                            )
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, 14)
                    }
                    .shadow(color: FactTrailTheme.primaryAction(for: colorScheme).opacity(configuration.isPressed ? 0.08 : 0.28), radius: configuration.isPressed ? 7 : 14, y: configuration.isPressed ? 2 : 4)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .saturation(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

struct FactTrailCheckInButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FactTrailTheme.aiAccent(for: colorScheme),
                                FactTrailTheme.aiAccent(for: colorScheme).opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: FactTrailTheme.aiAccent(for: colorScheme).opacity(configuration.isPressed ? 0.08 : 0.28), radius: configuration.isPressed ? 7 : 14, y: configuration.isPressed ? 2 : 4)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

struct FactTrailGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(configuration.isPressed ? 0.42 : 0.22))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: FactTrailTheme.glassOverlayColors(for: colorScheme),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[0].opacity(0.46),
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[1].opacity(0.36),
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[2].opacity(0.26)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.55
                            )
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.white.opacity(colorScheme == .dark ? 0.09 : 0.28))
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                    .shadow(color: FactTrailTheme.primaryAction(for: colorScheme).opacity(configuration.isPressed ? 0.03 : 0.08), radius: configuration.isPressed ? 7 : 18, x: -4, y: configuration.isPressed ? 2 : 6)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.13 : 0.05), radius: configuration.isPressed ? 7 : 18, y: configuration.isPressed ? 3 : 8)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .saturation(configuration.isPressed ? 1.25 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

struct FactTrailGlassCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.955 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.64), value: configuration.isPressed)
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

private struct FactTrailGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial.opacity(colorScheme == .dark ? 0.28 : 0.34))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: FactTrailTheme.glassOverlayColors(for: colorScheme),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[0].opacity(0.22),
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[1].opacity(0.16),
                                        FactTrailTheme.glassStrokeColors(for: colorScheme)[2].opacity(0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.55
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        FactTrailTheme.primaryAction(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.12),
                                        .white.opacity(colorScheme == .dark ? 0.12 : 0.24),
                                        FactTrailTheme.aiAccent(for: colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.10)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 5
                            )
                            .blur(radius: 5)
                            .opacity(0.42)
                            .padding(2)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.28))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                    .shadow(color: FactTrailTheme.primaryAction(for: colorScheme).opacity(colorScheme == .dark ? 0.06 : 0.05), radius: 18, x: -3, y: 5)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.05), radius: 20, y: 10)
            }
    }
}
