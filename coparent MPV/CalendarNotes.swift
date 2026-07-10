import SwiftUI

/// A lightweight note pinned to a range of calendar days - "Taking the kids on
/// vacation", "Grandma visiting" - purely an annotation on the timeline calendar.
/// It never changes the custody pattern or creates entries.
struct CalendarNote: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date

    init(id: UUID = UUID(), title: String, startDate: Date, endDate: Date) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Whether the note covers a given day (inclusive, day-granular).
    func covers(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: startDate) && day <= calendar.startOfDay(for: endDate)
    }

    /// "Jul 20 - Jul 27", or just "Jul 20" for a single day.
    var rangeText: String {
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        guard !Calendar.current.isDate(startDate, inSameDayAs: endDate) else { return start }
        return "\(start) - \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

enum CalendarNoteStore {
    private static let key = "coparoCalendarNotes"

    static func load() -> [CalendarNote] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CalendarNote].self, from: data)) ?? []
    }

    static func save(_ notes: [CalendarNote]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// The rose used for calendar notes everywhere they appear - distinct from entries
/// (blue), check-ins (teal), exchanges (amber), and documents (violet).
let calendarNoteColor = Color(hex: 0xB5546F)

/// Small bottom sheet for adding or editing a calendar note: a title and a date
/// range, nothing more.
struct CalendarNoteSheet: View {
    /// Nil when adding a new note.
    var existing: CalendarNote?
    let onSave: (CalendarNote) -> Void
    var onDelete: (CalendarNote) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date

    init(
        existing: CalendarNote? = nil,
        defaultDate: Date = Date(),
        onSave: @escaping (CalendarNote) -> Void,
        onDelete: @escaping (CalendarNote) -> Void = { _ in }
    ) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: existing?.title ?? "")
        _startDate = State(initialValue: existing?.startDate ?? defaultDate)
        _endDate = State(initialValue: existing?.endDate ?? defaultDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add a calendar note" : "Edit calendar note")
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Text("A label across the days it covers - it doesn't change your custody schedule.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            TextField("e.g. Taking the kids on vacation", text: $title)
                .font(.system(size: 15, weight: .regular, design: .default))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                }

            // Hotel-style range picker: tap the first day, then the last day.
            DateRangeCalendar(startDate: $startDate, endDate: $endDate)
                .padding(12)
                .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }

            Button {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onSave(CalendarNote(id: existing?.id ?? UUID(), title: trimmed, startDate: startDate, endDate: endDate))
                dismiss()
            } label: {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let existing {
                Button(role: .destructive) {
                    onDelete(existing)
                    dismiss()
                } label: {
                    Text("Remove note")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .presentationDetents([.height(existing == nil ? 620 : 656)])
        .presentationDragIndicator(.visible)
    }
}

/// A compact one-tap-then-second-tap date-range picker, like booking a hotel stay:
/// the first tap picks the start day, the next tap picks the end day (tapping an
/// earlier day restarts the selection; tapping after a complete range starts over).
struct DateRangeCalendar: View {
    @Binding var startDate: Date
    @Binding var endDate: Date

    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth: Date
    /// True between the first tap (start chosen) and the second (end chosen).
    @State private var isPickingEnd = false

    private let calendar = Calendar.current

    init(startDate: Binding<Date>, endDate: Binding<Date>) {
        _startDate = startDate
        _endDate = endDate
        _visibleMonth = State(initialValue: startDate.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Month header
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(visibleMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Spacer()
                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Weekday symbols
            HStack {
                ForEach(calendar.shortStandaloneWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }

            // Live selection hint - doubles as the instruction.
            Text(selectionHint)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(isPickingEnd ? calendarNoteColor : FactTrailTheme.mutedText(for: colorScheme))
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isStart = calendar.isDate(day, inSameDayAs: startDate)
        let isEnd = calendar.isDate(day, inSameDayAs: endDate)
        let inRange = day > startDate && day < endDate
        return Button {
            tapped(day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 14, weight: isStart || isEnd ? .bold : .regular, design: .default))
                .foregroundStyle(isStart || isEnd ? .white : FactTrailTheme.primaryText(for: colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if isStart || isEnd {
                        Circle().fill(calendarNoteColor)
                    } else if inRange {
                        Rectangle().fill(calendarNoteColor.opacity(0.14))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Hotel-style selection: start, then end; earlier tap or a third tap restarts.
    private func tapped(_ day: Date) {
        if isPickingEnd && day >= calendar.startOfDay(for: startDate) {
            endDate = day
            isPickingEnd = false
        } else {
            startDate = day
            endDate = day
            isPickingEnd = true
        }
    }

    private var selectionHint: String {
        if isPickingEnd {
            return "Now tap the last day (or Save for just this day)"
        }
        let start = startDate.formatted(.dateTime.month(.abbreviated).day())
        guard !calendar.isDate(startDate, inSameDayAs: endDate) else { return start }
        return "\(start) - \(endDate.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// The visible month's days, padded with nils so weekday columns line up.
    private var monthCells: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: monthInterval.start))
        }
        return cells
    }

    private func shiftMonth(by value: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
    }
}
