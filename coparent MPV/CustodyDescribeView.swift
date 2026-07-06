import SwiftUI

struct CustodyDescribeView: View {
    let userName: String
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private enum Stage { case describe, preview }
    @State private var stage: Stage = .describe
    @State private var text: String = ""
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var result: CustodyParseResult?
    @State private var anchorDate: Date = Date()
    @State private var showingManualEditor = false

    @State private var speechTranscriber = SpeechTranscriber()
    @State private var voiceBaseNotes = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch stage {
                case .describe: describeSection
                case .preview: previewSection
                }
            }
            .padding(20)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Custody schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadExisting)
        .onDisappear { speechTranscriber.stopTranscribing() }
        .onChange(of: speechTranscriber.transcript) { _, newTranscript in
            text = mergedNotes(base: voiceBaseNotes, transcript: newTranscript)
        }
        .sheet(isPresented: $showingManualEditor, onDismiss: { onSaved(); dismiss() }) {
            NavigationStack {
                CustodyScheduleView(
                    userName: userName,
                    onSave: { CustodyScheduleStore.save($0) },
                    onTurnOff: { CustodyScheduleStore.clear() },
                    initialSchedule: result?.schedule
                )
            }
        }
    }

    // MARK: Describe

    private var describeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Describe your custody schedule in your own words, and Coparo will map it onto your calendar. You can review it before anything is saved.")
                .font(.system(size: 14))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("e.g. I have the kids Monday to Wednesday and every other weekend. My co-parent Jordan has them the rest. I get them Christmas.")
                        .font(.system(size: 15))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            }
            .background(FactTrailTheme.surface(for: colorScheme))
            .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5) }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 12) {
                Button(action: toggleDictation) {
                    HStack(spacing: 8) {
                        Image(systemName: speechTranscriber.isRecording ? "stop.circle.fill" : "mic.fill")
                        Text(speechTranscriber.isRecording ? "Stop" : "Dictate")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(speechTranscriber.isRecording ? .red : FactTrailTheme.aiAccent(for: colorScheme))
                }
                .buttonStyle(.plain)
                if speechTranscriber.isRecording {
                    Text("Listening...")
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                Spacer()
            }

            if let speechError = speechTranscriber.errorMessage {
                Text(speechError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            Button(action: runParse) {
                HStack(spacing: 8) {
                    if isParsing { ProgressView().tint(.white) }
                    Text(isParsing ? "Mapping..." : "Map my schedule")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

            Button("Set it up manually instead") { showingManualEditor = true }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                .buttonStyle(.plain)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewSection: some View {
        if let result {
            VStack(alignment: .leading, spacing: 18) {
                Text("Here's what we heard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Text(result.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))

                previewGrid(schedule: scheduleWithAnchor(result.schedule))

                ForEach(result.holidayNotes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }

                HStack {
                    Text("Starts the week of")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Spacer()
                    DatePicker("", selection: $anchorDate, displayedComponents: .date)
                        .labelsHidden()
                        .onChange(of: anchorDate) { _, newValue in
                            // Snap to the start of the picked week so the repeating
                            // cycle always begins on a week boundary, matching the label.
                            var calendar = Calendar(identifier: .gregorian)
                            calendar.firstWeekday = 1
                            if let weekStart = calendar.dateInterval(of: .weekOfYear, for: newValue)?.start,
                               weekStart != anchorDate {
                                anchorDate = weekStart
                            }
                        }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }

                Button(action: save) { Text("Save schedule").frame(maxWidth: .infinity) }
                    .buttonStyle(FactTrailPrimaryButtonStyle())

                Button("Edit manually") { showingManualEditor = true }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                Button("Re-describe") { stage = .describe }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func previewGrid(schedule: CustodySchedule) -> some View {
        let start = Calendar.current.startOfDay(for: anchorDate)
        let days = (0..<14).map { Calendar.current.date(byAdding: .day, value: $0, to: start) ?? start }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(days, id: \.self) { day in
                let caregiver = schedule.caregiver(on: day)
                let color = CustodyPalette.color(caregiver?.colorIndex ?? 0)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(caregiver == nil ? FactTrailTheme.mutedText(for: colorScheme) : color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.opacity(caregiver == nil ? 0 : 0.16)))
            }
        }
    }

    // MARK: Logic

    private func loadExisting() {
        if let existing = CustodyScheduleStore.load() {
            result = CustodyParseResult(schedule: existing, summary: CustodyScheduleMapper.summary(for: existing), holidayNotes: [])
            anchorDate = existing.anchorDate
            stage = .preview
        }
    }

    private func scheduleWithAnchor(_ schedule: CustodySchedule) -> CustodySchedule {
        var copy = schedule
        copy.anchorDate = anchorDate
        return copy
    }

    private func runParse() {
        errorMessage = nil
        isParsing = true
        let description = text
        let caregivers = CustodyDescribeView.currentCaregivers(youName: youName)
        Task { @MainActor in
            defer { isParsing = false }
            do {
                let parser = CustodyScheduleParserFactory.make()
                if let parsed = try await parser.parse(description: description, existingCaregivers: caregivers, referenceDate: Date()) {
                    result = parsed
                    anchorDate = parsed.schedule.anchorDate
                    stage = .preview
                } else {
                    errorMessage = "I couldn't quite get that. Try rephrasing, or set it up manually."
                }
            } catch {
                errorMessage = "I couldn't map that right now. You can set it up manually."
            }
        }
    }

    private func save() {
        guard let result else { return }
        CustodyScheduleStore.save(scheduleWithAnchor(result.schedule))
        onSaved()
        dismiss()
    }

    private var youName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : trimmed
    }

    /// A custody schedule is only between two people: you and the co-parent (the
    /// person marked "Co-parent" in My people, or a default). Matches the manual editor.
    static func currentCaregivers(youName: String) -> [CustodyCaregiver] {
        let you = CustodyCaregiver(id: CustodyCaregiver.youID, name: youName, colorIndex: 0)
        if let coParent = PeopleStore.load().first(where: { $0.role == .coParent }) {
            return [you, CustodyCaregiver(id: coParent.id.uuidString, name: coParent.name, colorIndex: 1)]
        }
        return [you, CustodyCaregiver(id: "coparent-default", name: "Co-parent", colorIndex: 1)]
    }

    // MARK: Dictation

    // Mirrors the Add-note sheet in ContentView.swift exactly: startTranscribing()
    // is async and runs in a Task; the transcriber owns `isRecording` and updates
    // `transcript` live, which the .onChange above merges into the text field.
    private func toggleDictation() {
        if speechTranscriber.isRecording {
            speechTranscriber.stopTranscribing()
        } else {
            errorMessage = nil
            voiceBaseNotes = text
            Task { await speechTranscriber.startTranscribing() }
        }
    }

    private func mergedNotes(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }
        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty else { return cleanedTranscript }
        return "\(cleanedBase) \(cleanedTranscript)"
    }
}
