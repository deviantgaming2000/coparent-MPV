import SwiftUI

/// Distinct, theme-stable colors for custody caregivers, indexed by `CustodyCaregiver.colorIndex`.
enum CustodyPalette {
    private static let hexes: [UInt32] = [
        0x2F5D8C, // blue  (you)
        0x4F8F8B, // teal  (co-parent)
        0x7B6FAB, // purple
        0xD97706, // amber
        0x059669, // green
        0xB5546F, // rose
        0x2563EB  // bright blue
    ]

    static func color(_ index: Int) -> Color {
        Color(hex: hexes[((index % hexes.count) + hexes.count) % hexes.count])
    }
}

struct CustodyScheduleView: View {
    let userName: String
    let onSave: (CustodySchedule) -> Void
    let onTurnOff: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var hasExisting = false
    @State private var caregivers: [CustodyCaregiver] = []
    @State private var pattern: CustodyPattern = .weekOnOff
    @State private var anchorDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var customCycle: [String] = []
    @State private var customIsBiweekly = false
    @State private var overrides: [String: String] = [:]

    private var youName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    /// The two parties a preset alternates between: you and the first other caregiver.
    private var coParentID: String {
        caregivers.first { $0.id != CustodyCaregiver.youID }?.id ?? CustodyCaregiver.youID
    }

    /// The cycle the current choices produce, used for both preview and save.
    private var resolvedCycle: [String] {
        pattern == .custom ? customCycle : pattern.cycle(you: CustodyCaregiver.youID, coParent: coParentID)
    }

    private var previewSchedule: CustodySchedule {
        CustodySchedule(anchorDate: anchorDate, caregivers: caregivers, cycle: resolvedCycle, overrides: overrides, patternID: pattern.rawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Pick your parenting-time pattern. Coparo color-codes the calendar so you can see whose day each day is at a glance.")
                    .font(.system(size: 13))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                peopleSection
                patternSection
                if pattern == .custom {
                    customEditor
                }
                startDateSection
                previewSection
                saveArea
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Custody schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadState)
    }

    // MARK: People

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("People involved")
            ForEach(caregivers) { caregiver in
                HStack(spacing: 10) {
                    Circle()
                        .fill(CustodyPalette.color(caregiver.colorIndex))
                        .frame(width: 16, height: 16)
                    Text(caregiver.id == CustodyCaregiver.youID ? "\(caregiver.name) (you)" : caregiver.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Spacer()
                }
            }
            Text("Everyone from My people appears here. Add more in the My people menu.")
                .font(.system(size: 11))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
    }

    // MARK: Pattern

    private var patternSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Pattern")
            ForEach(CustodyPattern.allCases) { option in
                let isSelected = pattern == option
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { pattern = option }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme).opacity(0.6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Text(option.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Custom editor

    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Your week")
                Spacer()
                Picker("", selection: $customIsBiweekly) {
                    Text("1 week").tag(false)
                    Text("2 weeks").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: customIsBiweekly) { _, _ in resizeCustomCycle() }
            }
            Text("Tap a day to change who has the kids.")
                .font(.system(size: 12))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(customCycle.enumerated()), id: \.offset) { index, caregiverID in
                    let caregiver = caregivers.first { $0.id == caregiverID }
                    let color = CustodyPalette.color(caregiver?.colorIndex ?? 0)
                    Button {
                        cycleCustomDay(index)
                    } label: {
                        VStack(spacing: 2) {
                            Text(weekdayLetter(forCycleIndex: index))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(color)
                            Text(String((caregiver?.name.prefix(1)) ?? "?").uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
    }

    // MARK: Start date

    private var startDateSection: some View {
        HStack {
            Text("Pattern starts")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Spacer()
            DatePicker("", selection: $anchorDate, displayedComponents: .date)
                .labelsHidden()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Next two weeks")
            let start = Calendar.current.startOfDay(for: Date())
            let days = (0..<14).map { Calendar.current.date(byAdding: .day, value: $0, to: start) ?? start }
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(days, id: \.self) { day in
                    let caregiver = previewSchedule.caregiver(on: day)
                    let color = CustodyPalette.color(caregiver?.colorIndex ?? 0)
                    let isExchange = previewSchedule.isExchange(on: day)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(caregiver == nil ? FactTrailTheme.mutedText(for: colorScheme) : color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(caregiver == nil ? 0 : 0.14)))
                        .overlay {
                            if isExchange {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(CustodyPalette.color(3), lineWidth: 2)
                            }
                        }
                }
            }
            legend
        }
    }

    private var legend: some View {
        FlexibleWrap(spacing: 12) {
            ForEach(caregivers.filter { resolvedCycle.contains($0.id) || overrides.values.contains($0.id) }) { caregiver in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(CustodyPalette.color(caregiver.colorIndex).opacity(0.28))
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(CustodyPalette.color(caregiver.colorIndex), lineWidth: 1) }
                        .frame(width: 12, height: 12)
                    Text(caregiver.id == CustodyCaregiver.youID ? "Your days" : caregiver.name)
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                }
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).stroke(CustodyPalette.color(3), lineWidth: 2).frame(width: 12, height: 12)
                Text("Exchange")
                    .font(.system(size: 12))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            }
        }
        .padding(.top, 4)
    }

    // MARK: Save

    private var saveArea: some View {
        VStack(spacing: 10) {
            Button {
                onSave(previewSchedule)
                dismiss()
            } label: {
                Text("Save schedule").frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(resolvedCycle.isEmpty)

            if hasExisting {
                Button(role: .destructive) {
                    onTurnOff()
                    dismiss()
                } label: {
                    Text("Turn off schedule").frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
    }

    private func loadState() {
        caregivers = Self.buildCaregivers(youName: youName)
        let existing = CustodyScheduleStore.load()
        hasExisting = existing != nil

        if let existing {
            anchorDate = existing.anchorDate
            overrides = existing.overrides
            pattern = CustodyPattern(rawValue: existing.patternID) ?? .custom
            if pattern == .custom {
                customCycle = existing.cycle.isEmpty ? defaultCustomCycle() : existing.cycle
                customIsBiweekly = existing.cycle.count > 7
            }
            // Keep saved caregivers' colors if present, but refresh names/new people.
            if !existing.caregivers.isEmpty {
                caregivers = mergeCaregivers(saved: existing.caregivers, current: caregivers)
            }
        } else {
            customCycle = defaultCustomCycle()
        }
    }

    private func defaultCustomCycle() -> [String] {
        Array(repeating: CustodyCaregiver.youID, count: customIsBiweekly ? 14 : 7)
    }

    private func resizeCustomCycle() {
        let target = customIsBiweekly ? 14 : 7
        if customCycle.count < target {
            customCycle += Array(repeating: CustodyCaregiver.youID, count: target - customCycle.count)
        } else if customCycle.count > target {
            customCycle = Array(customCycle.prefix(target))
        }
    }

    private func cycleCustomDay(_ index: Int) {
        guard index < customCycle.count, !caregivers.isEmpty else { return }
        let currentID = customCycle[index]
        let currentPos = caregivers.firstIndex { $0.id == currentID } ?? 0
        let next = caregivers[(currentPos + 1) % caregivers.count]
        customCycle[index] = next.id
    }

    /// The weekday letter for a cycle slot, aligned so slot 0 is the anchor date's weekday.
    private func weekdayLetter(forCycleIndex index: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: index, to: anchorDate) ?? anchorDate
        return String(date.formatted(.dateTime.weekday(.narrow)))
    }

    private static func buildCaregivers(youName: String) -> [CustodyCaregiver] {
        var result: [CustodyCaregiver] = [CustodyCaregiver(id: CustodyCaregiver.youID, name: youName, colorIndex: 0)]
        for (offset, person) in PeopleStore.load().enumerated() {
            result.append(CustodyCaregiver(id: person.id.uuidString, name: person.name, colorIndex: offset + 1))
        }
        if result.count < 2 {
            result.append(CustodyCaregiver(id: "coparent-default", name: "Co-parent", colorIndex: 1))
        }
        return result
    }

    private func mergeCaregivers(saved: [CustodyCaregiver], current: [CustodyCaregiver]) -> [CustodyCaregiver] {
        var byID = Dictionary(uniqueKeysWithValues: saved.map { ($0.id, $0) })
        var merged = current.map { caregiver -> CustodyCaregiver in
            if var savedCaregiver = byID[caregiver.id] {
                savedCaregiver.name = caregiver.name
                byID[caregiver.id] = nil
                return savedCaregiver
            }
            return caregiver
        }
        // Keep any saved caregivers that are no longer in My people (still referenced by the cycle).
        for leftover in byID.values where resolvedCycle.contains(leftover.id) || overrides.values.contains(leftover.id) {
            merged.append(leftover)
        }
        return merged
    }
}

/// A minimal flow layout that wraps its children onto multiple lines.
struct FlexibleWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
