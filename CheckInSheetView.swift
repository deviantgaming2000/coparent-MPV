import SwiftUI

struct CheckInSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var locationManager = ExchangeLocationManager()
    @State private var selectedCategory: CheckInCategory = .handoff
    @State private var customLabel = ""
    @State private var showConfirmation = false
    @State private var savedCheckIn: CheckIn?

    let onSave: (CheckIn) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // The sheet uses the system drag indicator; content just needs top
            // breathing room beneath it.
            VStack(alignment: .leading, spacing: 16) {
                header
                categoryGrid
                otherCategoryField
                checkInButton
                cancelButton
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
        .onAppear {
            locationManager.captureLocation()
        }
        .overlay {
            if showConfirmation {
                Color.black.opacity(0.34)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showConfirmation, let savedCheckIn {
                CheckInConfirmationView(checkIn: savedCheckIn) {
                    showConfirmation = false
                    dismiss()
                }
                .padding(.horizontal, 0)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showConfirmation)
    }


    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's this check-in for?")
                .font(.system(size: 25, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Text("Pick one — we'll save your location and time automatically.")
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(locationStatusColor)
                .frame(width: 6, height: 6)

            Image("codoc-location-pin")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)

            Text(locationStatusText)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .lineLimit(1)
        }
        .foregroundStyle(locationStatusColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(FactTrailTheme.aiSoftBackground(for: colorScheme), in: Capsule())
        .overlay {
            Capsule()
                .stroke(locationStatusColor.opacity(0.24), lineWidth: 1)
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            ForEach(CheckInCategory.allCases) { category in
                CheckInCategoryCard(
                    category: category,
                    isSelected: selectedCategory == category
                ) {
                    selectedCategory = category
                }
            }
        }
    }

    @ViewBuilder
    private var otherCategoryField: some View {
        if selectedCategory == .other {
            TextField("What is this check-in for?", text: $customLabel)
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(14)
                .background(FactTrailTheme.background(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        }
    }

    private var checkInButton: some View {
        Button {
            saveCheckIn()
        } label: {
            HStack(spacing: 8) {
                Image("codoc-location-pin")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)

                Text("Check in now")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(FactTrailCheckInButtonStyle())
        .disabled(!canSave)
        .padding(.top, 2)
    }

    private var cancelButton: some View {
        Button("Cancel") {
            dismiss()
        }
        .font(.system(size: 16, weight: .semibold, design: .default))
        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var locationStatusText: String {
        if locationManager.isCapturing {
            return "Capturing"
        }

        return locationManager.latitude == nil ? "Location unavailable" : "Captured"
    }

    private var locationStatusColor: Color {
        locationManager.latitude == nil && !locationManager.isCapturing ? FactTrailTheme.mutedText(for: colorScheme) : FactTrailTheme.aiAccent(for: colorScheme)
    }

    private var canSave: Bool {
        if selectedCategory == .other {
            return !customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return true
    }

    private func saveCheckIn() {
        guard savedCheckIn == nil else {
            showConfirmation = true
            return
        }

        let checkIn = CheckIn(
            category: selectedCategory,
            customLabel: selectedCategory == .other ? customLabel.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            latitude: locationManager.latitude ?? 0,
            longitude: locationManager.longitude ?? 0,
            address: locationManager.address,
            followUpCompleted: false
        )

        savedCheckIn = checkIn
        onSave(checkIn)
        showConfirmation = true
    }
}

private struct CheckInCategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    isSelected ? FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10) : FactTrailTheme.surface(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct CheckInCategoryCard: View {
    let category: CheckInCategory
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(category.iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(iconColor)
                    .frame(width: 34, height: 34)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(category.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(FactTrailGlassCardButtonStyle())
    }

    private var cardBackground: Color {
        isSelected ? FactTrailTheme.aiSoftBackground(for: colorScheme) : FactTrailTheme.surface(for: colorScheme)
    }

    private var iconBackground: Color {
        isSelected ? FactTrailTheme.aiAccent(for: colorScheme).opacity(0.16) : FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.55)
    }

    private var iconColor: Color {
        isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme)
    }

    private var borderColor: Color {
        isSelected ? FactTrailTheme.aiAccent(for: colorScheme).opacity(0.62) : FactTrailTheme.border(for: colorScheme)
    }
}

private extension CheckInCategory {
    var iconAssetName: String {
        switch self {
        case .handoff:
            return "codoc-handoff"
        case .schoolPickupDropOff:
            return "codoc-school"
        case .doctorTherapy:
            return "codoc-medical-heart"
        case .mediation:
            return "codoc-people"
        case .courtAppearance:
            return "codoc-court-gavel"
        case .other:
            return "codoc-info-circle"
        }
    }
}

private struct CheckInConfirmationView: View {
    let checkIn: CheckIn
    let onDone: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(FactTrailTheme.border(for: colorScheme))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            Image("codoc-location-pin")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                .frame(width: 86, height: 86)
                .background(FactTrailTheme.aiSoftBackground(for: colorScheme), in: Circle())
                .overlay {
                    Circle()
                        .stroke(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.28), lineWidth: 3)
                }

            VStack(spacing: 8) {
                Text("Checked in.")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Text("Location and time are saved.")
                    .font(.system(size: 21, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
            }

            FlowLayout(spacing: 8, rowSpacing: 8) {
                CheckInTag(text: checkIn.displayLabel, style: .accent)
                CheckInTag(text: DateFormatter.factTrailCompactDateTime.string(from: checkIn.createdAt), style: .accent)
            }
            .frame(maxWidth: .infinity)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 20, weight: .bold, design: .default))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity)
        .background(FactTrailTheme.surface(for: colorScheme), in: UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 30, style: .continuous))
    }
}

private enum CheckInTagStyle {
    case accent
    case muted
}

private struct CheckInTag: View {
    let text: String
    var style: CheckInTagStyle = .accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .default))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(backgroundColor, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(borderColor, lineWidth: style == .accent ? 1 : 0)
            }
    }

    private var textColor: Color {
        switch style {
        case .accent:
            return FactTrailTheme.aiAccent(for: colorScheme)
        case .muted:
            return FactTrailTheme.mutedText(for: colorScheme)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .accent:
            return FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10)
        case .muted:
            return FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.46)
        }
    }

    private var borderColor: Color {
        FactTrailTheme.aiAccent(for: colorScheme).opacity(0.22)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                widestRow = max(widestRow, currentX - spacing)
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }

            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        widestRow = max(widestRow, currentX - spacing)
        return CGSize(width: maxWidth == 0 ? widestRow : maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
