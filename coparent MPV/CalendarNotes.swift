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

            VStack(spacing: 0) {
                HStack {
                    Text("From")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: startDate) { _, newValue in
                            if endDate < newValue { endDate = newValue }
                        }
                }
                .padding(12)
                Divider()
                HStack {
                    Text("To")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Spacer()
                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(12)
            }
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
        .presentationDetents([.height(existing == nil ? 380 : 420)])
        .presentationDragIndicator(.visible)
    }
}
