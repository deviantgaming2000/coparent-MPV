import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @AppStorage("hasAcceptedFactTrailDisclaimer") private var hasAcceptedDisclaimer = false
    @AppStorage("factTrailAppearance") private var appearanceRawValue = FactTrailAppearance.dark.rawValue
    @AppStorage("factTrailUserName") private var userName = ""
    @State private var incidents: [Incident] = []
    @State private var exchangeRecords: [ExchangeRecord] = []
    @State private var entries: [Entry] = []
    @State private var checkIns: [CheckIn] = []
    @State private var linkedNotes: [LinkedNote] = []
    @State private var storedDocuments: [StoredDocument] = []
    @State private var path: [AppRoute] = []
    @State private var activeReviewSummary: IncidentSummaryDraft?
    @State private var isShowingReview = false
    @State private var pendingExchangeDraft: IncidentDraft?
    @State private var pendingExchangeRecordID: UUID?
    @State private var saveErrorMessage: String?
    @State private var shouldShowNamePrompt = false
    @State private var shouldShowCheckInSheet = false
    @State private var pendingCheckInFollowUp: CheckIn?
    @State private var pendingCheckInIncidentDraft: IncidentDraft?
    @State private var pendingCheckInIncidentID: UUID?
    @State private var isShowingLaunchScreen = true

    private let incidentStore = IncidentStore()
    private let exchangeRecordStore = ExchangeRecordStore()
    private let entryStore = EntryStore()
    private let checkInStore = CheckInStore()
    private let aiService: any AIService = AIServiceFactory.makeService()
    private let documentStore = DocumentStore()
    private let linkedNotesStorageKey = "factTrailLinkedNotes"

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasAcceptedDisclaimer {
                    HomeView(
                        incidents: incidents,
                        exchangeRecords: exchangeRecords,
                        checkIns: checkIns,
                        userName: userName,
                        selectedAppearance: appearanceBinding,
                        onExchangeRecord: { path.append(.exchangeRecord) },
                        onDocumentSomething: { path.append(.entry) },
                        onOpenDocuments: { path.append(.documents) },
                        onCheckIn: { shouldShowCheckInSheet = true },
                        onViewTimeline: { path.append(.timeline) },
                        onViewInsights: { path.append(.insights) },
                        onEditName: { shouldShowNamePrompt = true },
                        onOpenIncident: { incident in
                            path.append(.edit(incident.id))
                        },
                        onOpenExchangeRecord: { _ in
                            path.append(.timeline)
                        }
                    )
                } else {
                    OnboardingView {
                        hasAcceptedDisclaimer = true
                        shouldShowNamePrompt = true
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .entry:
                    IncidentEntryView(
                        aiService: aiService,
                        onCreateSummary: { summary in
                            openReview(for: summary)
                        },
                        onSaveCreatedIncident: { incident in
                            saveIncident(incident)
                            path.removeAll()
                        }
                    )
                case .entryFromExchange:
                    IncidentEntryView(
                        initialDraft: pendingExchangeDraft ?? IncidentDraft(),
                        aiService: aiService,
                        onCreateSummary: { summary in
                            openReview(for: summary)
                        },
                        onSaveCreatedIncident: { incident in
                            saveIncident(incident)
                            if let pendingExchangeRecordID {
                                attachIncident(incident.id, toExchangeRecordID: pendingExchangeRecordID)
                            }
                            pendingExchangeDraft = nil
                            pendingExchangeRecordID = nil
                            path.removeAll()
                        }
                    )
                case .entryFromCheckIn:
                    IncidentEntryView(
                        initialDraft: pendingCheckInIncidentDraft ?? IncidentDraft(),
                        aiService: aiService,
                        onCreateSummary: { summary in
                            openReview(for: summary)
                        },
                        onSaveCreatedIncident: { incident in
                            saveIncident(incident)
                            if let pendingCheckInIncidentID {
                                resolveCheckInFollowUp(id: pendingCheckInIncidentID, status: .incidentLogged)
                            }
                            pendingCheckInIncidentDraft = nil
                            pendingCheckInIncidentID = nil
                            path.removeAll()
                        }
                    )
                case .review:
                    EmptyView()
                case .timeline:
                    TimelineView(
                        incidents: incidents,
                        exchangeRecords: exchangeRecords,
                        checkIns: checkIns,
                        linkedNotes: linkedNotes,
                        attachmentsProvider: { attachments(forTimelineItemID: $0) },
                        saveErrorMessage: saveErrorMessage,
                        onEdit: { incident in
                            path.append(.edit(incident.id))
                        },
                        onAddLinkedNote: { item, note in
                            addLinkedNote(note, to: item)
                        },
                        onDeleteAttachment: { document in
                            deleteDocument(document)
                        },
                        onInsights: { path = [.insights] }
                    )
                case .insights:
                    InsightsScreenView(
                        entries: timelineEntryInputs,
                        aiService: aiService,
                        onHome: { path = [] },
                        onTimeline: { path = [.timeline] }
                    )
                case .exchangeRecord:
                    ExchangeRecordEntryView(
                        onSaveRoutine: { record in
                            saveExchangeRecord(record)
                            path.removeAll()
                        },
                        onExpandIncident: { record, draft in
                            saveExchangeRecord(record)
                            pendingExchangeRecordID = record.id
                            pendingExchangeDraft = draft
                            path.append(.entryFromExchange)
                        }
                    )
                case .edit(let incidentID):
                    if let incident = incidents.first(where: { $0.id == incidentID }) {
                        IncidentEntryView(
                            initialDraft: incident.draft,
                            mode: .edit,
                            aiService: aiService,
                            onCreateSummary: { _ in },
                            onSaveEdit: { draft in
                                updateIncident(incident.updated(from: draft))
                                path.removeLast()
                            }
                        )
                    } else {
                        ContentUnavailableView("No Incident Selected", systemImage: "doc.text")
                    }
                case .documents:
                    MyDocumentsView(
                        documents: storedDocuments,
                        onAddDocument: { document in
                            addDocument(document)
                        },
                        onUpdateDocument: { document in
                            updateDocument(document)
                        },
                        onDeleteDocument: { document in
                            deleteDocument(document)
                        }
                    )
                }
            }
        }
        .preferredColorScheme(selectedAppearance.colorScheme)
        .tint(FactTrailTheme.primaryAction(for: selectedAppearance.colorScheme))
        .overlay {
            if isShowingLaunchScreen {
                FactTrailSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(10)
            }
        }
        .navigationDestination(isPresented: $isShowingReview) {
            if let activeReviewSummary {
                SummaryReviewView(
                    summaryDraft: activeReviewSummary,
                    onSave: {
                        let incident = activeReviewSummary.incident
                        saveIncident(incident)
                        if let pendingExchangeRecordID {
                            attachIncident(incident.id, toExchangeRecordID: pendingExchangeRecordID)
                        }
                        self.activeReviewSummary = nil
                        self.pendingExchangeDraft = nil
                        self.pendingExchangeRecordID = nil
                        if let pendingCheckInIncidentID {
                            resolveCheckInFollowUp(id: pendingCheckInIncidentID, status: .incidentLogged)
                        }
                        self.pendingCheckInIncidentDraft = nil
                        self.pendingCheckInIncidentID = nil
                        self.isShowingReview = false
                        path.removeAll()
                    },
                    onEdit: {
                        isShowingReview = false
                    },
                    onCancel: {
                        self.activeReviewSummary = nil
                        self.pendingExchangeDraft = nil
                        self.pendingExchangeRecordID = nil
                        self.isShowingReview = false
                        path.removeAll()
                    }
                )
            } else {
                EmptyView()
            }
        }
        .onAppear {
            UITableView.appearance().backgroundColor = .clear
            UITableViewCell.appearance().backgroundColor = .clear
            incidents = incidentStore.loadIncidents()
            exchangeRecords = exchangeRecordStore.loadExchangeRecords()
            entries = entryStore.loadEntries()
            checkIns = checkInStore.loadCheckIns()
            linkedNotes = loadLinkedNotes()
            storedDocuments = documentStore.loadDocuments()

            if hasAcceptedDisclaimer && userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shouldShowNamePrompt = true
            }
        }
        .task {
            guard isShowingLaunchScreen else { return }
            try? await Task.sleep(for: .seconds(1.45))
            withAnimation(.easeInOut(duration: 0.45)) {
                isShowingLaunchScreen = false
            }
            presentPendingCheckInFollowUpIfNeeded()
        }
        .sheet(isPresented: $shouldShowNamePrompt) {
            UserNameSetupView(userName: $userName)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $shouldShowCheckInSheet) {
            CheckInSheetView { checkIn in
                saveCheckIn(checkIn)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(item: $pendingCheckInFollowUp) { checkIn in
            CheckInFollowUpSheetView(
                checkIn: checkIn,
                onNoIssues: {
                    resolveCheckInFollowUp(id: checkIn.id, status: .noIssues, note: "No issues reported")
                },
                onSaveNote: { note in
                    resolveCheckInFollowUp(id: checkIn.id, status: .noteAdded, note: note)
                },
                onLogIncident: {
                    startIncidentFromCheckIn(checkIn)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }

    private var selectedAppearance: FactTrailAppearance {
        FactTrailAppearance(rawValue: appearanceRawValue) ?? .dark
    }

    private var appearanceBinding: Binding<FactTrailAppearance> {
        Binding(
            get: { selectedAppearance },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private func saveIncident(_ incident: Incident) {
        incidents.insert(taggedIncident(incident), at: 0)
        persistIncidents()
    }

    private func updateIncident(_ incident: Incident) {
        guard let index = incidents.firstIndex(where: { $0.id == incident.id }) else {
            return
        }

        incidents[index] = taggedIncident(incident)
        incidents.sort { $0.incidentDate > $1.incidentDate }
        persistIncidents()
    }

    private func openReview(for summary: IncidentSummaryDraft) {
        Task { @MainActor in
            activeReviewSummary = summary
            await Task.yield()
            isShowingReview = true
        }
    }

    private func saveExchangeRecord(_ record: ExchangeRecord) {
        var taggedRecord = record
        if taggedRecord.tags.isEmpty {
            taggedRecord.tags = tagsForExchangeRecord(record)
        }
        exchangeRecords.insert(taggedRecord, at: 0)
        persistExchangeRecords()
    }

    private func saveCheckIn(_ checkIn: CheckIn) {
        var taggedCheckIn = checkIn
        if taggedCheckIn.tags.isEmpty {
            taggedCheckIn.tags = tagsForCheckIn(checkIn)
        }
        checkIns.insert(taggedCheckIn, at: 0)
        persistCheckIns()
    }

    private func taggedIncident(_ incident: Incident) -> Incident {
        guard incident.tags.isEmpty else {
            return incident
        }

        let text = [
            incident.category,
            incident.originalNotes,
            incident.neutralSummary,
            incident.finalDocumentationSummary,
            incident.peopleInvolved,
            incident.location,
            incident.evidenceNotes,
            incident.patternTags.map(\.displayName).joined(separator: " ")
        ].joined(separator: " ")

        return incident.withTags(EntryTagger.tags(for: text))
    }

    private func tagsForExchangeRecord(_ record: ExchangeRecord) -> [EntryTag] {
        var text = [
            "exchange handoff",
            record.role.rawValue,
            record.timing.rawValue,
            record.timingDescription,
            record.address
        ].joined(separator: " ")

        if record.timing == .late {
            text += " late minutes late"
        }

        return EntryTagger.tags(for: text)
    }

    private func tagsForCheckIn(_ checkIn: CheckIn) -> [EntryTag] {
        EntryTagger.tags(for: [
            "check in",
            checkIn.displayLabel,
            checkIn.address,
            checkIn.notes ?? ""
        ].joined(separator: " "))
    }

    private func presentPendingCheckInFollowUpIfNeeded() {
        guard hasAcceptedDisclaimer,
              !shouldShowNamePrompt,
              !shouldShowCheckInSheet,
              pendingCheckInFollowUp == nil else {
            return
        }

        pendingCheckInFollowUp = checkIns
            .filter(\.needsFollowUp)
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    private func resolveCheckInFollowUp(id: UUID, status: CheckInFollowUpStatus, note: String? = nil) {
        guard let index = checkIns.firstIndex(where: { $0.id == id }) else {
            return
        }

        checkIns[index].followUpCompleted = true
        checkIns[index].followUpResolvedAt = Date()
        checkIns[index].followUpStatus = status
        if let note {
            checkIns[index].notes = note
        }
        pendingCheckInFollowUp = nil
        persistCheckIns()
    }

    private func addNote(_ note: String, toCheckInID checkInID: UUID) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = checkIns.firstIndex(where: { $0.id == checkInID }) else {
            return
        }

        let existing = checkIns[index].notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        checkIns[index].notes = existing.isEmpty ? trimmed : "\(existing)\n\n\(trimmed)"
        checkIns[index].followUpCompleted = true
        checkIns[index].followUpResolvedAt = Date()
        checkIns[index].followUpStatus = .noteAdded
        checkIns[index].tags = EntryTagger.tags(for: [
            checkIns[index].displayLabel,
            checkIns[index].address,
            checkIns[index].notes ?? ""
        ].joined(separator: " "))
        checkIns.sort { $0.createdAt > $1.createdAt }
        persistCheckIns()
    }

    private func addLinkedNote(_ text: String, to item: TimelineItem) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let note = LinkedNote(
            parentItemID: item.id,
            parentItemType: item.typeLabel,
            text: trimmed
        )
        linkedNotes.append(note)
        persistLinkedNotes()
    }

    private func loadLinkedNotes() -> [LinkedNote] {
        guard let data = UserDefaults.standard.data(forKey: linkedNotesStorageKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([LinkedNote].self, from: data)
        } catch {
            return []
        }
    }

    private func persistLinkedNotes() {
        do {
            let data = try JSONEncoder().encode(linkedNotes)
            UserDefaults.standard.set(data, forKey: linkedNotesStorageKey)
        } catch {
            saveErrorMessage = "Note could not be saved."
        }
    }

    private func addDocument(_ document: StoredDocument) {
        storedDocuments.insert(document, at: 0)
        persistDocuments()
    }

    private func updateDocument(_ document: StoredDocument) {
        guard let index = storedDocuments.firstIndex(where: { $0.id == document.id }) else { return }
        storedDocuments[index] = document
        persistDocuments()
    }

    private func deleteDocument(_ document: StoredDocument) {
        if let relativePath = document.localFilePath {
            documentStore.deleteFile(atRelativePath: relativePath)
        }
        storedDocuments.removeAll { $0.id == document.id }
        persistDocuments()
    }

    private func persistDocuments() {
        do {
            try documentStore.saveDocuments(storedDocuments)
        } catch {
            saveErrorMessage = "Documents could not be saved."
        }
    }

    private func attachments(forTimelineItemID id: String) -> [StoredDocument] {
        storedDocuments
            .filter { $0.linkedTimelineItemIds.contains(id) }
            .sorted { $0.importedAt > $1.importedAt }
    }

    /// Normalized view of every logged entry, fed to the AI/heuristic insights engine.
    private var timelineEntryInputs: [TimelineEntryInput] {
        let incidentsByExchangeID = Dictionary(
            uniqueKeysWithValues: incidents.compactMap { incident -> (UUID, Incident)? in
                guard let exchangeRecordID = incident.exchangeRecordID else { return nil }
                return (exchangeRecordID, incident)
            }
        )
        let items: [TimelineItem] =
            incidents.filter { $0.exchangeRecordID == nil }.map(TimelineItem.incident)
            + exchangeRecords.map { TimelineItem.exchangeRecord($0, incidentsByExchangeID[$0.id]) }
            + checkIns.map(TimelineItem.checkIn)

        return makeTimelineInputs(from: items)
    }


    private func startIncidentFromCheckIn(_ checkIn: CheckIn) {
        var draft = IncidentDraft()
        draft.incidentDate = checkIn.createdAt
        draft.location = checkIn.address
        draft.category = .other
        draft.originalNotes = "Follow-up from \(checkIn.displayLabel) check-in on \(DateFormatter.factTrailDateTime.string(from: checkIn.createdAt))."
        pendingCheckInIncidentDraft = draft
        pendingCheckInIncidentID = checkIn.id
        pendingCheckInFollowUp = nil
        path.append(.entryFromCheckIn)
    }

    private func attachIncident(_ incidentID: UUID, toExchangeRecordID exchangeRecordID: UUID) {
        guard let index = exchangeRecords.firstIndex(where: { $0.id == exchangeRecordID }) else {
            return
        }

        exchangeRecords[index].attachedIncidentID = incidentID
        exchangeRecords.sort { $0.exchangeDate > $1.exchangeDate }
        persistExchangeRecords()
    }

    private func persistIncidents() {
        do {
            try incidentStore.saveIncidents(incidents)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Incident could not be saved on this device."
        }
    }

    private func persistExchangeRecords() {
        do {
            try exchangeRecordStore.saveExchangeRecords(exchangeRecords)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Exchange record could not be saved on this device."
        }
    }

    private func persistCheckIns() {
        do {
            try checkInStore.saveCheckIns(checkIns)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Check-in could not be saved on this device."
        }
    }
}

private struct FactTrailSplashView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            animatedBackground

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.58))
                        .frame(width: 118, height: 118)
                        .overlay {
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.62), FactTrailTheme.primaryAction(for: .dark).opacity(0.48), .white.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        }
                        .shadow(color: FactTrailTheme.primaryAction(for: .dark).opacity(0.32), radius: 34, x: -12, y: 18)
                        .shadow(color: FactTrailTheme.aiAccent(for: .dark).opacity(0.28), radius: 34, x: 12, y: -12)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FactTrailTheme.primaryAction(for: .dark),
                                    FactTrailTheme.aiAccent(for: .dark),
                                    FactTrailTheme.primaryAction(for: .dark).opacity(0.72)
                                ],
                                startPoint: isAnimating ? .bottomLeading : .topLeading,
                                endPoint: isAnimating ? .topTrailing : .bottomTrailing
                            )
                        )
                        .frame(width: 76, height: 76)
                        .overlay {
                            Text("C")
                                .font(.system(size: 38, weight: .black, design: .default))
                                .foregroundStyle(.white)
                        }
                        .scaleEffect(isAnimating ? 1.05 : 0.96)
                }

                VStack(spacing: 6) {
                    Text("Coparo")
                        .font(.system(size: 38, weight: .bold, design: .default))
                        .foregroundStyle(.white)

                    Text("A clear record, quietly kept.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(34)
            .background {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .padding(28)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private var animatedBackground: some View {
        ZStack {
            LinearGradient(
                colors: FactTrailTheme.backgroundColors(for: .dark),
                startPoint: isAnimating ? .topTrailing : .topLeading,
                endPoint: isAnimating ? .bottomLeading : .bottomTrailing
            )

            Circle()
                .fill(FactTrailTheme.primaryAction(for: .dark).opacity(0.24))
                .frame(width: 280, height: 280)
                .blur(radius: 54)
                .offset(x: isAnimating ? 140 : -120, y: isAnimating ? -220 : -120)

            Circle()
                .fill(FactTrailTheme.aiAccent(for: .dark).opacity(0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 62)
                .offset(x: isAnimating ? -160 : 150, y: isAnimating ? 230 : 170)
        }
    }
}

/// Maps the UI's timeline items to the neutral inputs consumed by the insights engine.
private func makeTimelineInputs(from items: [TimelineItem]) -> [TimelineEntryInput] {
    items.map { item in
        let kind: EntryKind
        switch item {
        case .incident: kind = item.isFlagged ? .flag : .entry
        case .exchangeRecord: kind = .exchange
        case .checkIn: kind = .checkin
        }
        return TimelineEntryInput(
            id: item.id,
            date: item.date,
            kind: kind,
            title: item.title,
            text: item.summary,
            tags: item.tags.map(\.displayName),
            flagged: item.isFlagged,
            location: item.locationText
        )
    }
}

private enum AppRoute: Hashable {
    case entry
    case entryFromExchange
    case entryFromCheckIn
    case review
    case timeline
    case insights
    case exchangeRecord
    case edit(UUID)
    case documents
}

private enum EntryMode {
    case create
    case edit
}

struct LinkedNote: Identifiable, Codable, Hashable {
    let id: UUID
    let parentItemID: String
    let parentItemType: String
    var text: String
    let createdAt: Date
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        parentItemID: String,
        parentItemType: String,
        text: String,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.parentItemID = parentItemID
        self.parentItemType = parentItemType
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private enum TimelineItem: Identifiable {
    case incident(Incident)
    case exchangeRecord(ExchangeRecord, Incident?)
    case checkIn(CheckIn)

    var id: String {
        switch self {
        case .incident(let incident):
            return "incident-\(incident.id)"
        case .exchangeRecord(let record, _):
            return "exchange-\(record.id)"
        case .checkIn(let checkIn):
            return "checkin-\(checkIn.id)"
        }
    }

    var date: Date {
        switch self {
        case .incident(let incident):
            return incident.incidentDate
        case .exchangeRecord(let record, _):
            return record.exchangeDate
        case .checkIn(let checkIn):
            return checkIn.createdAt
        }
    }

    var typeLabel: String {
        switch self {
        case .incident:
            return "Entry"
        case .exchangeRecord:
            return "Exchange"
        case .checkIn:
            return "Check-in"
        }
    }

    var title: String {
        switch self {
        case .incident(let incident):
            return incident.category
        case .exchangeRecord(let record, let attachedIncident):
            if attachedIncident != nil {
                return "Child exchange"
            }
            return record.role.rawValue
        case .checkIn(let checkIn):
            return checkIn.displayLabel
        }
    }

    var summary: String {
        switch self {
        case .incident(let incident):
            let finalSummary = incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalSummary.isEmpty {
                return finalSummary
            }
            let neutralSummary = incident.neutralSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !neutralSummary.isEmpty {
                return neutralSummary
                    .components(separatedBy: .newlines)
                    .first { $0.hasPrefix("Summary:") }?
                    .replacingOccurrences(of: "Summary: ", with: "")
                ?? neutralSummary
            }
            return incident.originalNotes
        case .exchangeRecord(let record, let attachedIncident):
            if let attachedIncident {
                let finalSummary = attachedIncident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !finalSummary.isEmpty {
                    return finalSummary
                }
                return attachedIncident.originalNotes
            }
            return [record.role.rawValue, record.timingDescription, record.address]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
        case .checkIn(let checkIn):
            if let notes = checkIn.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                return notes
            }
            let address = checkIn.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? "Location and time saved." : address
        }
    }

    var locationText: String {
        switch self {
        case .incident(let incident):
            return incident.location
        case .exchangeRecord(let record, _):
            return record.address
        case .checkIn(let checkIn):
            return checkIn.address
        }
    }

    var attachmentCount: Int {
        switch self {
        case .incident(let incident):
            return incident.evidenceAttachments.count
        case .exchangeRecord(_, let attachedIncident):
            return attachedIncident?.evidenceAttachments.count ?? 0
        case .checkIn:
            return 0
        }
    }

    var isFlagged: Bool {
        switch self {
        case .incident(let incident):
            return incident.patternTags.contains(.safetyConcern)
        case .exchangeRecord(_, let attachedIncident):
            return attachedIncident != nil
        case .checkIn(let checkIn):
            return !checkIn.followUpCompleted
        }
    }

    var tags: [EntryTag] {
        let storedTags: [EntryTag]
        switch self {
        case .incident(let incident):
            storedTags = incident.tags
        case .exchangeRecord(let record, let attachedIncident):
            storedTags = record.tags.isEmpty ? (attachedIncident?.tags ?? []) : record.tags
        case .checkIn(let checkIn):
            storedTags = checkIn.tags
        }

        if !storedTags.isEmpty {
            return storedTags
        }

        return EntryTagger.tags(for: [title, summary, locationText].joined(separator: " "))
    }

    var checkInID: UUID? {
        if case .checkIn(let checkIn) = self {
            return checkIn.id
        }
        return nil
    }

    var editableIncident: Incident? {
        switch self {
        case .incident(let incident):
            return incident
        case .exchangeRecord(_, let attachedIncident):
            return attachedIncident
        case .checkIn:
            return nil
        }
    }
}

private struct OnboardingView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coparo")
                        .font(.largeTitle.bold())
                    Text("A calm place to organize parenting documentation and preserve important records.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Documentation Only")
                        .font(.title3.bold())
                    Text("This app helps you record events, organize facts, and create neutral summaries for your own records.")
                    Text("This app does not provide legal advice.")
                        .font(.headline)
                }
                .padding()
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Preserve Original Records")
                        .font(.title3.bold())
                    PreservationReminder(text: "Do not delete text messages.")
                    PreservationReminder(text: "Turn off auto-delete for messages where possible.")
                    PreservationReminder(text: "Save screenshots, call logs, emails, school records, medical records, and exchange details.")
                    PreservationReminder(text: "Preserve original records.")
                }

                Button(action: onAccept) {
                    Text("I Understand")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailPrimaryButtonStyle())
                .controlSize(.large)
            }
            .padding(24)
        }
        .factTrailScreenBackground()
    }
}

private struct PreservationReminder: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UserNameSetupView: View {
    @Binding var userName: String
    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Coparo")
                    .font(.title.bold())

                Text("What should the app call you?")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            TextField("Your name", text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .factTrailGlassCard(cornerRadius: 18)

            Text("This stays on this device for now. Later this can come from your Apple or Google account.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                saveName()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(trimmedDraftName.isEmpty)

            Spacer(minLength: 0)
        }
        .padding(24)
        .factTrailScreenBackground()
        .interactiveDismissDisabled(userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .onAppear {
            draftName = userName
        }
    }

    private var trimmedDraftName: String {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveName() {
        userName = trimmedDraftName
        dismiss()
    }
}

private struct HomeView: View {
    let incidents: [Incident]
    let exchangeRecords: [ExchangeRecord]
    let checkIns: [CheckIn]
    let userName: String
    @Binding var selectedAppearance: FactTrailAppearance
    let onExchangeRecord: () -> Void
    let onDocumentSomething: () -> Void
    let onOpenDocuments: () -> Void
    let onCheckIn: () -> Void
    let onViewTimeline: () -> Void
    var onViewInsights: () -> Void = {}
    let onEditName: () -> Void
    let onOpenIncident: (Incident) -> Void
    let onOpenExchangeRecord: (ExchangeRecord) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    header
                    greetingBlock

                    if let latestItem {
                        HomeLastLoggedCard(
                            item: latestItem,
                            onOpenIncident: onOpenIncident,
                            onOpenExchangeRecord: onOpenExchangeRecord,
                            onOpenTimeline: onViewTimeline
                        )
                    }

                    VStack(spacing: 0) {
                        HomeActionCard(
                            iconAssetName: "codoc-document-incident",
                            title: "Log an incident",
                            subtitle: "Describe what happened or just talk it out.",
                            style: .primary,
                            action: onDocumentSomething
                        )

                        HomeActionCard(
                            iconAssetName: "codoc-location-pin",
                            title: "Check in",
                            subtitle: "Quickly log a handoff, appointment, or meetup.",
                            footnote: "Grabs your location and time",
                            style: .checkIn,
                            action: onCheckIn
                        )

                        HomeActionCard(
                            iconAssetName: "codoc-timeline-spine",
                            title: "Your timeline",
                            subtitle: "Everything you've logged, in order.",
                            style: .standard,
                            action: onViewTimeline
                        )

                        HomeActionCard(
                            iconAssetName: "codoc-folder",
                            title: "My documents",
                            subtitle: "Store screenshots, files, and supporting records.",
                            style: .standard,
                            action: onOpenDocuments
                        )

                        HomeActionCard(
                            iconAssetName: "codoc-info-circle",
                            title: "Pick up where you left off",
                            subtitle: "Two entries could use a little more detail.",
                            badgeText: "2",
                            style: .standard,
                            action: onDocumentSomething
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 18)
            }

            HomeBottomNavigation(activeTab: .home, onTimeline: onViewTimeline, onInsights: onViewInsights)
        }
        .background(HomePalette.background(for: colorScheme).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            Menu {
                Button("Edit Name", action: onEditName)

                Picker("Theme", selection: $selectedAppearance) {
                    ForEach(FactTrailAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
            } label: {
                Image("codoc-menu")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 17)
                .foregroundStyle(HomePalette.primaryText(for: colorScheme))
                .frame(width: 42, height: 42, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Menu")

            Spacer()

            Button(action: onEditName) {
                Text(userInitial)
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HomePalette.primaryAction(for: colorScheme),
                                        HomePalette.aiAccent(for: colorScheme)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    .overlay {
                        Circle()
                            .stroke(HomePalette.background(for: colorScheme), lineWidth: 4)
                            .padding(4)
                    }
                    .overlay {
                        Circle()
                            .stroke(HomePalette.primaryAction(for: colorScheme), lineWidth: 2)
                    }
            }
            .buttonStyle(HomePressButtonStyle())
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Hey, \(displayName).")
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(HomePalette.primaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            HomeStatusLine(text: statusText)
        }
    }

    private var displayName: String {
        userName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init) ?? "there"
    }

    private var userInitial: String {
        displayName.first.map { String($0).uppercased() } ?? "F"
    }

    private var statusText: String {
        guard let latestItem else {
            return "Nothing logged yet."
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(latestItem.date) {
            return "Last logged today."
        }

        if calendar.isDateInYesterday(latestItem.date) {
            return "Nothing logged since yesterday."
        }

        let weekday = DateFormatter.factTrailWeekday.string(from: latestItem.date)
        return "Nothing logged since \(weekday)."
    }

    private var latestItem: TimelineItem? {
        allRecentItems.first
    }

    private var allRecentItems: [TimelineItem] {
        let incidentsByExchangeID = Dictionary(
            uniqueKeysWithValues: incidents.compactMap { incident -> (UUID, Incident)? in
                guard let exchangeRecordID = incident.exchangeRecordID else {
                    return nil
                }
                return (exchangeRecordID, incident)
            }
        )
        let exchangeItems = exchangeRecords.map { record in
            TimelineItem.exchangeRecord(record, incidentsByExchangeID[record.id])
        }
        let standaloneIncidentItems = incidents
            .filter { $0.exchangeRecordID == nil }
            .map(TimelineItem.incident)
        let checkInItems = checkIns.map(TimelineItem.checkIn)

        return (standaloneIncidentItems + exchangeItems + checkInItems)
            .sorted { $0.date > $1.date }
    }

    private func searchableText(for item: TimelineItem) -> String {
        switch item {
        case .incident(let incident):
            return [
                "incident",
                incident.category,
                incident.originalNotes,
                incident.neutralSummary,
                incident.finalDocumentationSummary,
                incident.peopleInvolved,
                incident.location,
                incident.evidenceNotes,
                incident.evidenceTypes.map(\.rawValue).joined(separator: " "),
                incident.patternTags.map(\.displayName).joined(separator: " "),
                incident.guidedAnswers.map { "\($0.question) \($0.answer)" }.joined(separator: " ")
            ].joined(separator: " ")
        case .exchangeRecord(let record, let attachedIncident):
            return [
                "exchange record",
                record.role.rawValue,
                record.timing.rawValue,
                record.timingDescription,
                record.address,
                record.coordinateDescription,
                attachedIncident.map { searchableText(for: .incident($0)) } ?? ""
            ].joined(separator: " ")
        case .checkIn(let checkIn):
            return [
                "check in",
                checkIn.displayLabel,
                checkIn.address,
                checkIn.notes ?? ""
            ].joined(separator: " ")
        }
    }
}

private enum HomePalette {
    static func background(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.background(for: colorScheme)
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.surface(for: colorScheme)
    }

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.primaryText(for: colorScheme)
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.secondaryText(for: colorScheme)
    }

    static func mutedText(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.mutedText(for: colorScheme)
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.border(for: colorScheme)
    }

    static func primaryAction(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.primaryAction(for: colorScheme)
    }

    static func aiAccent(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.aiAccent(for: colorScheme)
    }

    static func aiSoftBackground(for colorScheme: ColorScheme) -> Color {
        FactTrailTheme.aiSoftBackground(for: colorScheme)
    }
}

private struct HomeStatusLine: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(HomePalette.primaryAction(for: colorScheme))
                .frame(width: 7, height: 7)
                .scaleEffect(isPulsing ? 1.55 : 1)
                .opacity(isPulsing ? 0.48 : 0.95)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isPulsing)

            Text(text)
                .font(.system(size: 16, weight: .medium, design: .default))
                .foregroundStyle(HomePalette.mutedText(for: colorScheme))
        }
        .onAppear {
            isPulsing = true
        }
    }
}

private struct HomeLastLoggedCard: View {
    let item: TimelineItem
    let onOpenIncident: (Incident) -> Void
    let onOpenExchangeRecord: (ExchangeRecord) -> Void
    let onOpenTimeline: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: openItem) {
            HStack(spacing: 12) {
                Image(iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(HomePalette.secondaryText(for: colorScheme))
                    .frame(width: 19, height: 19)
                    .frame(width: 42, height: 42)
                    .background(HomePalette.border(for: colorScheme).opacity(colorScheme == .dark ? 0.36 : 0.58), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("LAST LOGGED")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .tracking(2)
                        .foregroundStyle(HomePalette.mutedText(for: colorScheme))

                    Text(compactTitle)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(HomePalette.primaryText(for: colorScheme))
                        .lineLimit(1)

                    Text(preview)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(HomePalette.secondaryText(for: colorScheme))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isFlagged {
                    Text("Flagged")
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(HomePalette.primaryAction(for: colorScheme))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(HomePalette.primaryAction(for: colorScheme).opacity(0.12), in: Capsule())
                }

                Image("codoc-chevron-right")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(HomePalette.mutedText(for: colorScheme).opacity(0.45))
            }
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(HomePalette.surface(for: colorScheme))
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.12), radius: 18, y: 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(HomePalette.border(for: colorScheme), lineWidth: 1)
            }
        }
        .buttonStyle(HomePressButtonStyle())
    }

    private var compactTitle: String {
        "\(title) · \(DateFormatter.factTrailCompactDateTime.string(from: item.date))"
    }

    private var title: String {
        switch item {
        case .incident(let incident):
            return incident.category
        case .exchangeRecord:
            return "Child exchange"
        case .checkIn(let checkIn):
            return checkIn.displayLabel
        }
    }

    private var iconAssetName: String {
        switch item {
        case .incident:
            return "codoc-document-incident"
        case .exchangeRecord:
            return "codoc-handoff"
        case .checkIn:
            return "codoc-location-pin"
        }
    }

    private var preview: String {
        switch item {
        case .incident(let incident):
            let finalSummary = incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalSummary.isEmpty {
                return finalSummary
            }

            return incident.neutralSummary
                .components(separatedBy: .newlines)
                .first { $0.hasPrefix("Summary:") }?
                .replacingOccurrences(of: "Summary: ", with: "")
            ?? incident.originalNotes
        case .exchangeRecord(let record, let attachedIncident):
            if let attachedIncident {
                return attachedIncident.finalDocumentationSummary.isEmpty
                    ? "\(record.role.rawValue), \(record.timingDescription)"
                    : attachedIncident.finalDocumentationSummary
            }

            return "\(record.role.rawValue), \(record.timingDescription)"
        case .checkIn(let checkIn):
            let address = checkIn.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? "Location and time saved." : address
        }
    }

    private var isFlagged: Bool {
        switch item {
        case .incident(let incident):
            return incident.childInvolved || incident.patternTags.contains(.safetyConcern)
        case .exchangeRecord(let record, let attachedIncident):
            return record.timing != .onTime || attachedIncident != nil
        case .checkIn:
            return false
        }
    }

    private func openItem() {
        switch item {
        case .incident(let incident):
            onOpenIncident(incident)
        case .exchangeRecord(let record, let attachedIncident):
            if let attachedIncident {
                onOpenIncident(attachedIncident)
            } else {
                onOpenExchangeRecord(record)
            }
        case .checkIn:
            onOpenTimeline()
        }
    }
}

private enum HomeActionCardStyle {
    case primary
    case checkIn
    case standard
}

private struct HomeActionCard: View {
    let iconAssetName: String
    let title: String
    let subtitle: String
    var footnote: String?
    var badgeText: String?
    let style: HomeActionCardStyle
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(iconColor)
                    .frame(width: 23, height: 23)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(titleColor)

                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 12, weight: .semibold, design: .default))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(HomePalette.aiAccent(for: colorScheme), in: Circle())
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 15, weight: .regular, design: .default))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)

                    if let footnote {
                        HStack(spacing: 7) {
                            LocationPulseDot(color: HomePalette.aiAccent(for: colorScheme))
                            Text(footnote)
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundStyle(HomePalette.aiAccent(for: colorScheme))
                        }
                        .padding(.top, 5)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, style == .primary ? 20 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: style == .primary ? 0 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: style == .primary ? 16 : 14, style: .continuous))
        }
        .buttonStyle(HomePressButtonStyle())
        .padding(.top, style == .primary ? 0 : 10)
    }

    private var cardBackground: some View {
        Group {
            if style == .primary {
                // Prototype primary card: mostly-blue gradient (primary → mix(primary 72%, accent)),
                // matching the Save button rather than a full blue→teal sweep.
                LinearGradient(
                    colors: FactTrailTheme.primaryButtonColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if style == .checkIn {
                HomePalette.aiSoftBackground(for: colorScheme)
            } else {
                HomePalette.surface(for: colorScheme)
            }
        }
    }

    private var borderColor: Color {
        style == .checkIn
            ? HomePalette.aiAccent(for: colorScheme).opacity(0.28)
            : HomePalette.border(for: colorScheme)
    }

    private var titleColor: Color {
        style == .primary ? .white : HomePalette.primaryText(for: colorScheme)
    }

    private var subtitleColor: Color {
        style == .primary ? .white.opacity(0.78) : HomePalette.secondaryText(for: colorScheme)
    }

    private var iconColor: Color {
        switch style {
        case .primary:
            return .white.opacity(0.88)
        case .checkIn:
            return HomePalette.aiAccent(for: colorScheme)
        case .standard:
            return HomePalette.secondaryText(for: colorScheme)
        }
    }
}

private struct HomeBottomNavigation: View {
    var activeTab: BottomNavTab = .home
    var onHome: () -> Void = {}
    let onTimeline: () -> Void
    var onInsights: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            HomeBottomNavItem(title: "Home", iconAssetName: "codoc-log-target", isActive: activeTab == .home, action: onHome)

            HomeBottomNavItem(title: "Timeline", iconAssetName: "codoc-timeline-spine", isActive: activeTab == .timeline, action: onTimeline)

            HomeBottomNavItem(title: "Insights", iconAssetName: "codoc-insights-chart", isActive: activeTab == .insights, action: onInsights)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background(HomePalette.surface(for: colorScheme).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(HomePalette.border(for: colorScheme))
                .frame(height: 1)
        }
    }
}

private enum BottomNavTab {
    case home, timeline, insights
}

private struct HomeBottomNavItem: View {
    let title: String
    let iconAssetName: String
    let isActive: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .default))
            }
            .foregroundStyle(isActive ? HomePalette.primaryAction(for: colorScheme) : HomePalette.mutedText(for: colorScheme))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(HomePressButtonStyle())
    }
}

private struct HomePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

/// Solid dot with an expanding "radar ping" ring behind it — mirrors the prototype's
/// `.location-pulse` (loc-ring keyframes: scale 0.8→2, opacity 0.6→0, 2s ease-out, looping).
private struct LocationPulseDot: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                // Ring drawn in an overlay so its growth never affects layout.
                Circle()
                    .strokeBorder(color, lineWidth: 1.5)
                    .scaleEffect(animating ? 2.6 : 1.0)
                    .opacity(animating ? 0 : 0.6)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

private struct HomeRecentActivityCard: View {
    let item: TimelineItem
    let onOpenIncident: (Incident) -> Void
    let onOpenExchangeRecord: (ExchangeRecord) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: openItem) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label(title, systemImage: iconName)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(DateFormatter.factTrailDateTime.string(from: item.date))
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                }

                Text(preview)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let statusText {
                    Text(statusText)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                        .foregroundStyle(statusColor)
                }
            }
            .padding(16)
            .factTrailGlassCard(cornerRadius: 20)
        }
        .buttonStyle(FactTrailGlassCardButtonStyle())
    }

    private var title: String {
        switch item {
        case .incident(let incident):
            return incident.category
        case .exchangeRecord:
            return "Exchange Record"
        case .checkIn(let checkIn):
            return checkIn.displayLabel
        }
    }

    private var iconName: String {
        switch item {
        case .incident:
            return "doc.text"
        case .exchangeRecord:
            return "arrow.left.arrow.right.circle"
        case .checkIn:
            return "mappin.and.ellipse"
        }
    }

    private var preview: String {
        switch item {
        case .incident(let incident):
            let finalSummary = incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalSummary.isEmpty {
                return finalSummary
            }

            return incident.neutralSummary
                .components(separatedBy: .newlines)
                .first { $0.hasPrefix("Summary:") }?
                .replacingOccurrences(of: "Summary: ", with: "")
            ?? incident.originalNotes
        case .exchangeRecord(let record, let attachedIncident):
            if attachedIncident != nil {
                return "\(record.role.rawValue) • \(record.timingDescription)"
            }

            let address = record.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty
                ? "\(record.role.rawValue) • \(record.timingDescription)"
                : "\(record.role.rawValue) • \(record.timingDescription)\n\(address)"
        case .checkIn(let checkIn):
            let address = checkIn.address.trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? "Location and time saved." : address
        }
    }

    private var statusText: String? {
        switch item {
        case .incident(let incident):
            return incident.finalDocumentationSummary.isEmpty ? nil : "Final summary saved"
        case .exchangeRecord(let record, let attachedIncident):
            if attachedIncident != nil || record.attachedIncidentID != nil {
                return "Expanded incident attached"
            }
            return record.timing.rawValue
        case .checkIn(let checkIn):
            return checkIn.followUpCompleted ? "Complete" : "Follow-up available"
        }
    }

    private var statusColor: Color {
        switch item {
        case .incident:
            return FactTrailTheme.aiAccent(for: colorScheme)
        case .exchangeRecord(let record, let attachedIncident):
            if attachedIncident != nil || record.attachedIncidentID != nil {
                return .orange
            }
            return record.timing == .onTime ? FactTrailTheme.primaryAction(for: colorScheme) : .orange
        case .checkIn:
            return FactTrailTheme.aiAccent(for: colorScheme)
        }
    }

    private func openItem() {
        switch item {
        case .incident(let incident):
            onOpenIncident(incident)
        case .exchangeRecord(let record, let attachedIncident):
            if let attachedIncident {
                onOpenIncident(attachedIncident)
            } else {
                onOpenExchangeRecord(record)
            }
        case .checkIn:
            break
        }
    }
}

private struct IncidentEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: IncidentDraft
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingAttachments = false
    @State private var attachmentErrorMessage: String?
    @State private var isAnalyzing = false
    @State private var aiSuggestion: AISuggestion?
    @State private var aiSuggestionErrorMessage: String?
    @State private var isGeneratingFinalDocumentation = false
    @State private var finalDocumentationErrorMessage: String?
    @State private var isShowingOptionalDetails: Bool
    @State private var isShowingEvidenceOptions: Bool
    @State private var incidentLocationManager = ExchangeLocationManager()
    @State private var speechTranscriber = SpeechTranscriber()
    @State private var voiceBaseNotes = ""
    @State private var isShowingDateClarification = false
    @State private var userProvidedIncidentDate: Bool
    @State private var localReviewSummary: IncidentSummaryDraft?
    @State private var isShowingLocalReview = false

    let mode: EntryMode
    let aiService: any AIService
    let onCreateSummary: (IncidentSummaryDraft) -> Void
    let onSaveCreatedIncident: ((Incident) -> Void)?
    let onSaveEdit: ((IncidentDraft) -> Void)?

    init(
        initialDraft: IncidentDraft = IncidentDraft(),
        mode: EntryMode = .create,
        aiService: any AIService = MockAIService(),
        onCreateSummary: @escaping (IncidentSummaryDraft) -> Void,
        onSaveCreatedIncident: ((Incident) -> Void)? = nil,
        onSaveEdit: ((IncidentDraft) -> Void)? = nil
    ) {
        _draft = State(initialValue: initialDraft)
        _aiSuggestion = State(initialValue: initialDraft.aiAnalysis)
        _isShowingOptionalDetails = State(initialValue: mode == .edit)
        _isShowingEvidenceOptions = State(initialValue: mode == .edit)
        _userProvidedIncidentDate = State(initialValue: mode == .edit)
        self.mode = mode
        self.aiService = aiService
        self.onCreateSummary = onCreateSummary
        self.onSaveCreatedIncident = onSaveCreatedIncident
        self.onSaveEdit = onSaveEdit
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                incidentTextCard
                attachmentPills
                optionalSpecificsSection

                if mode == .edit {
                    editSummarySection
                }

                if isLoadingAttachments || attachmentErrorMessage != nil || !draft.evidenceAttachments.isEmpty {
                    attachmentStatusSection
                }

                saveArea
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
        .navigationTitle(mode == .create ? "New entry" : "Edit entry")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if mode == .create {
                incidentLocationManager.captureLocation()
            }
        }
        .onDisappear {
            speechTranscriber.stopTranscribing()
        }
        .onChange(of: speechTranscriber.transcript) { _, newTranscript in
            draft.originalNotes = mergedNotes(base: voiceBaseNotes, transcript: newTranscript)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(mode == .create ? "Back" : "Cancel") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isShowingDateClarification) {
            IncidentDateClarificationSheet(
                selectedDate: $draft.incidentDate,
                onConfirm: {
                    userProvidedIncidentDate = true
                    isShowingDateClarification = false
                    commitSaveEntry()
                },
                onSkip: {
                    draft.incidentDate = Date()
                    isShowingDateClarification = false
                    commitSaveEntry()
                }
            )
            .presentationDetents([.height(470)])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $isShowingLocalReview) {
            if let localReviewSummary {
                SummaryReviewView(
                    summaryDraft: localReviewSummary,
                    onSave: {
                        onSaveCreatedIncident?(localReviewSummary.incident)
                        self.localReviewSummary = nil
                        self.isShowingLocalReview = false
                    },
                    onEdit: {
                        isShowingLocalReview = false
                    },
                    onCancel: {
                        self.localReviewSummary = nil
                        self.isShowingLocalReview = false
                    }
                )
            } else {
                EmptyView()
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await loadAttachments(from: newItems)
            }
        }
        .onChange(of: draft.category) { _, _ in
            if !isAnalyzing {
                draft.patternTags = NeutralSummaryGenerator.suggestedPatternTags(for: draft)
            }
        }
    }

    private var incidentTextCard: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $draft.originalNotes)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .lineSpacing(6)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 56)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .overlay(alignment: .topLeading) {
                    if draft.originalNotes.isEmpty {
                        Text("Describe what happened. Include specifics if you can, or just talk and we'll follow up.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.82))
                            .lineSpacing(8)
                            .padding(.horizontal, 21)
                            .padding(.top, 24)
                            .allowsHitTesting(false)
                    }
                }

            Button {
                toggleDictation()
            } label: {
                Image("codoc-microphone")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .frame(width: 38, height: 38)
                    .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12), in: Circle())
            }
            .buttonStyle(HomePressButtonStyle())
            .padding(.trailing, 12)
            .padding(.bottom, 11)
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 12, y: 4)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            FactTrailTheme.aiAccent(for: colorScheme).opacity(0.85),
                            FactTrailTheme.primaryAction(for: colorScheme).opacity(0.42)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 0)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
    }

    private var attachmentPills: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                AttachmentPill(iconAssetName: "codoc-photo", title: "Photo")
            }

            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 6, matching: .images) {
                AttachmentPill(iconAssetName: "codoc-screenshot", title: "Screenshot")
            }

            Button {
                isShowingEvidenceOptions = true
            } label: {
                AttachmentPill(iconAssetName: "codoc-file", title: "File")
            }
            .buttonStyle(.plain)
        }
    }

    private var optionalSpecificsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isShowingOptionalDetails.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image("codoc-plus")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                    Text(isShowingOptionalDetails ? "Hide specifics" : "Add specifics (date, time, location, etc.)")
                }
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            .buttonStyle(.plain)

            if isShowingOptionalDetails {
                VStack(alignment: .leading, spacing: 13) {
                    SpecificsDateRow(date: $draft.incidentDate) {
                        userProvidedIncidentDate = true
                    }
                    SpecificsTextRow(iconAssetName: "codoc-people", placeholder: "People involved", text: $draft.peopleInvolved)
                    SpecificsTextRow(iconAssetName: "codoc-location-pin", placeholder: "Location", text: $draft.location)
                    Toggle("Child involved?", isOn: $draft.childInvolved)
                    Picker("Category", selection: $draft.category) {
                        ForEach(IncidentCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                }
                .padding(16)
                .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 8, y: 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 2)
    }

    private var editSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Final documentation summary")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            TextEditor(text: $draft.neutralSummaryOverride)
                .frame(minHeight: 120)
                .padding(12)
                .scrollContentBackground(.hidden)
                .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        }
    }

    private var attachmentStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoadingAttachments {
                HStack {
                    ProgressView()
                    Text("Adding selected images...")
                        .font(.footnote)
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                }
            }

            if let attachmentErrorMessage {
                Text(attachmentErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !draft.evidenceAttachments.isEmpty {
                EvidenceAttachmentGrid(attachments: draft.evidenceAttachments, onRemove: removeAttachment)
            }
        }
    }

    private var saveArea: some View {
        VStack(spacing: 12) {
            Button {
                saveEntry()
            } label: {
                Text(mode == .create ? "Save entry" : "Save changes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(!draft.canCreateSummary)

            if mode == .create {
                Button {
                    saveEntry()
                } label: {
                    Text("Save and finish this later")
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(!draft.canCreateSummary)
            }
        }
        .padding(.top, 10)
    }

    private func saveEntry() {
        if mode == .create && !userProvidedIncidentDate {
            isShowingDateClarification = true
            return
        }

        commitSaveEntry()
    }

    private func commitSaveEntry() {
        speechTranscriber.stopTranscribing()
        applyCapturedIncidentLocationIfNeeded()
        if mode == .create {
            if draft.patternTags.isEmpty {
                draft.patternTags = NeutralSummaryGenerator.suggestedPatternTags(for: draft)
            }
            let summary = NeutralSummaryGenerator.makeSummary(from: draft)
            if onSaveCreatedIncident != nil {
                localReviewSummary = summary
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(220))
                    isShowingLocalReview = true
                }
            } else {
                onCreateSummary(summary)
            }
        } else {
            onSaveEdit?(draft)
        }
    }

    private func toggleDictation() {
        if speechTranscriber.isRecording {
            speechTranscriber.stopTranscribing()
        } else {
            voiceBaseNotes = draft.originalNotes
            Task {
                await speechTranscriber.startTranscribing()
            }
        }
    }

    private func mergedNotes(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else {
            return base
        }

        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty else {
            return cleanedTranscript
        }

        return "\(cleanedBase)\n\n\(cleanedTranscript)"
    }

    private func loadAttachments(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            draft.evidenceAttachments = []
            attachmentErrorMessage = nil
            return
        }

        isLoadingAttachments = true
        attachmentErrorMessage = nil

        var attachments: [EvidenceAttachment] = []

        for (index, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      UIImage(data: data) != nil else {
                    continue
                }

                attachments.append(
                    EvidenceAttachment(
                        id: UUID(),
                        fileName: "evidence-\(index + 1).jpg",
                        data: data
                    )
                )
            } catch {
                attachmentErrorMessage = "One selected image could not be added."
            }
        }

        draft.evidenceAttachments = attachments
        isLoadingAttachments = false
    }

    private func removeAttachment(_ attachment: EvidenceAttachment) {
        draft.evidenceAttachments.removeAll { $0.id == attachment.id }
    }

    private func refreshGuidedQuestions() {
        let existingAnswers = Dictionary(uniqueKeysWithValues: draft.guidedAnswers.map { ($0.question, $0) })
        draft.guidedAnswers = NeutralSummaryGenerator.followUpQuestions(for: draft.category)
            .prefix(5)
            .map { question in
                GuidedQuestionAnswer(
                    id: existingAnswers[question]?.id ?? UUID(),
                    question: question,
                    answer: existingAnswers[question]?.answer ?? ""
                )
            }
    }

    private func applyAIQuestions(_ questions: [AIFollowUpQuestion]) {
        draft.guidedAnswers = questions.map { question in
            GuidedQuestionAnswer(
                id: UUID(),
                question: question.question,
                answer: ""
            )
        }
    }

    private func applyAIEvidenceTypes(from analysis: AIIncidentAnalysis) {
        let detectedText = [
            analysis.evidenceMentioned.joined(separator: " "),
            draft.originalNotes,
            draft.evidenceNotes
        ]
        .joined(separator: " ")
        .lowercased()
        var detectedTypes = Set(draft.evidenceTypes)

        if detectedText.contains("text") || detectedText.contains("message") {
            detectedTypes.insert(.textMessages)
        }
        if detectedText.contains("screenshot") {
            detectedTypes.insert(.screenshots)
        }
        if detectedText.contains("email") {
            detectedTypes.insert(.emails)
        }
        if detectedText.contains("photo") || detectedText.contains("picture") {
            detectedTypes.insert(.photos)
        }
        if detectedText.contains("call log") || detectedText.contains("phone log") {
            detectedTypes.insert(.callLogs)
        }
        if detectedText.contains("school") || detectedText.contains("teacher") {
            detectedTypes.insert(.schoolRecords)
        }
        if detectedText.contains("medical") || detectedText.contains("doctor") || detectedText.contains("clinic") {
            detectedTypes.insert(.medicalRecords)
        }
        if detectedText.contains("exchange") || detectedText.contains("pickup") || detectedText.contains("drop off") || detectedText.contains("drop-off") {
            detectedTypes.insert(.exchangeRecords)
        }

        draft.evidenceTypes = EvidenceType.allCases.filter { detectedTypes.contains($0) }
    }

    private func applyCapturedIncidentLocationIfNeeded() {
        let capturedLocation = capturedIncidentLocationDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !capturedLocation.isEmpty else {
            return
        }

        let currentLocation = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentLocation.isEmpty {
            draft.location = capturedLocation
        } else if !currentLocation.contains("Captured location") && !currentLocation.contains("GPS:") {
            draft.location = "\(currentLocation)\nCaptured location: \(capturedLocation)"
        }
    }

    private var capturedIncidentLocationDescription: String {
        guard let latitude = incidentLocationManager.latitude,
              let longitude = incidentLocationManager.longitude else {
            return ""
        }

        let gpsText = String(format: "GPS: %.5f, %.5f", latitude, longitude)
        let address = incidentLocationManager.address.trimmingCharacters(in: .whitespacesAndNewlines)

        if address.isEmpty {
            return gpsText
        }

        return "\(address)\n\(gpsText)"
    }

    private func analyzeWithAI() {
        applyCapturedIncidentLocationIfNeeded()
        resetAnalysisStateForFreshRun()
        isAnalyzing = true
        aiSuggestionErrorMessage = nil
        AIDebugLogger.log("User incident text", draft.originalNotes)
        AIDebugLogger.log("Final UI state before analysis", debugUIState)

        Task {
            do {
                let suggestion = try await aiService.analyzeIncident(draft: draft)
                AIDebugLogger.log("Raw/parsed AIService response delivered to UI", suggestion.debugSummary)
                draft.category = suggestion.suggestedCategory
                applyAIQuestions(suggestion.followUpQuestions)
                applyAIEvidenceTypes(from: suggestion)
                draft.patternTags = suggestion.patternTags
                draft.aiAnalysis = suggestion
                draft.finalDocumentation = nil
                aiSuggestion = suggestion
                AIDebugLogger.log("Final UI state after analysis", debugUIState)
            } catch {
                aiSuggestionErrorMessage = error.localizedDescription
                AIDebugLogger.log("AIService error", error.localizedDescription)
            }

            isAnalyzing = false
        }
    }

    private func resetAnalysisStateForFreshRun() {
        aiSuggestion = nil
        aiSuggestionErrorMessage = nil
        finalDocumentationErrorMessage = nil
        draft.guidedAnswers = []
        draft.patternTags = []
        draft.aiAnalysis = nil
        draft.finalDocumentation = nil
        draft.neutralSummaryOverride = ""
    }

    private func generateFinalDocumentation() {
        applyCapturedIncidentLocationIfNeeded()
        isGeneratingFinalDocumentation = true
        finalDocumentationErrorMessage = nil

        Task {
            do {
                let finalDocumentation = try await aiService.generateFinalDocumentation(
                    draft: draft,
                    analysis: aiSuggestion ?? draft.aiAnalysis
                )
                draft.finalDocumentation = finalDocumentation
                draft.neutralSummaryOverride = finalDocumentation.summary
                AIDebugLogger.log("Final documentation UI state", "\(finalDocumentation.completeness.score)% \(finalDocumentation.completeness.status)")
            } catch {
                finalDocumentationErrorMessage = error.localizedDescription
                AIDebugLogger.log("Final documentation error", error.localizedDescription)
            }

            isGeneratingFinalDocumentation = false
        }
    }

    private var debugUIState: String {
        """
        category=\(draft.category.rawValue)
        notes=\(draft.originalNotes)
        questions=\(draft.guidedAnswers.map(\.question))
        tags=\(draft.patternTags.map(\.rawValue))
        missingShown=\(aiSuggestion?.missingInformation ?? [])
        """
    }

    private func guidedAnswerBinding(for question: String) -> Binding<String>? {
        guard let index = draft.guidedAnswers.firstIndex(where: { $0.question == question }) else {
            return nil
        }

        return $draft.guidedAnswers[index].answer
    }

    private func evidenceTypeBinding(for evidenceType: EvidenceType) -> Binding<Bool> {
        Binding(
            get: { draft.evidenceTypes.contains(evidenceType) },
            set: { isSelected in
                if isSelected {
                    if !draft.evidenceTypes.contains(evidenceType) {
                        draft.evidenceTypes.append(evidenceType)
                    }
                } else {
                    draft.evidenceTypes.removeAll { $0 == evidenceType }
                }
                draft.patternTags = NeutralSummaryGenerator.suggestedPatternTags(for: draft)
            }
        )
    }

    private func patternTagBinding(for tag: PatternTag) -> Binding<Bool> {
        Binding(
            get: { draft.patternTags.contains(tag) },
            set: { isSelected in
                if isSelected {
                    if !draft.patternTags.contains(tag) {
                        draft.patternTags.append(tag)
                    }
                } else {
                    draft.patternTags.removeAll { $0 == tag }
                }
            }
        )
    }

    private var shouldShowAIDebugPanel: Bool {
        #if DEBUG
        return false
        #else
        return false
        #endif
    }

    private var aiServiceMode: AIServiceMode {
        (aiService as? AIServiceStatusProviding)?.serviceMode ?? .mock
    }
}

private struct AttachmentPill: View {
    let iconAssetName: String
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(iconAssetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))

            Text(title)
                .font(.system(size: 12.5, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(FactTrailTheme.surface(for: colorScheme), in: Capsule())
        .overlay {
            Capsule()
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 8, y: 2)
    }
}

private struct SpecificsDateRow: View {
    @Binding var date: Date
    let onDateChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SpecificsIcon(assetName: "codoc-calendar")

            DatePicker("Date and time", selection: $date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: date) { _, _ in
                    onDateChanged()
                }
        }
    }
}

private struct SpecificsTextRow: View {
    let iconAssetName: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            SpecificsIcon(assetName: iconAssetName)

            TextField(placeholder, text: $text, axis: .vertical)
                .font(.system(size: 13.5, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .lineLimit(1...3)
                .padding(.bottom, 5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(FactTrailTheme.border(for: colorScheme))
                        .frame(height: 1)
                }
        }
    }
}

private struct SpecificsIcon: View {
    let assetName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 13, height: 13)
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            .frame(width: 28, height: 28)
            .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct IncidentDateClarificationSheet: View {
    @Binding var selectedDate: Date
    let onConfirm: () -> Void
    let onSkip: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedOption: DateClarificationOption?
    @State private var customDateText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(FactTrailTheme.aiAccent(for: colorScheme))
                        .frame(width: 6, height: 6)
                    Text("ONE QUICK THING")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .tracking(2)
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                }

                Text("When did this happen?")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Text("We'll use today's time automatically. If it happened earlier, let us know.")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    .lineSpacing(4)
            }

            HStack(spacing: 10) {
                ForEach(DateClarificationOption.allCases) { option in
                    DateClarificationChip(
                        option: option,
                        isSelected: selectedOption == option,
                        referenceDate: Date()
                    ) {
                        selectedOption = option
                        selectedDate = option.date(from: Date())
                    }
                }
            }

            HStack(spacing: 12) {
                Image("codoc-calendar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

                TextField("Or type a date and time...", text: $customDateText)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Button {
                    // Placeholder for future date dictation.
                } label: {
                    Image("codoc-microphone")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        .frame(width: 30, height: 30)
                        .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
            }

            VStack(spacing: 10) {
                Button {
                    if selectedOption == nil {
                        selectedDate = Date()
                    }
                    onConfirm()
                } label: {
                    Text("Save entry")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailPrimaryButtonStyle())

                Button(action: onSkip) {
                    Text("Skip for now — we'll note when we received this")
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
    }
}

private enum DateClarificationOption: CaseIterable, Identifiable {
    case justNow
    case earlierToday
    case yesterday

    var id: Self { self }

    var title: String {
        switch self {
        case .justNow:
            return "Just now"
        case .earlierToday:
            return "Earlier today"
        case .yesterday:
            return "Yesterday"
        }
    }

    func subtitle(from date: Date) -> String {
        switch self {
        case .justNow:
            return DateFormatter.factTrailTime.string(from: date)
        case .earlierToday:
            return DateFormatter.factTrailMonthDay.string(from: date)
        case .yesterday:
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
            return DateFormatter.factTrailWeekdayMonthDay.string(from: yesterday)
        }
    }

    func date(from date: Date) -> Date {
        switch self {
        case .justNow, .earlierToday:
            return date
        case .yesterday:
            return Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
    }
}

private struct DateClarificationChip: View {
    let option: DateClarificationOption
    let isSelected: Bool
    let referenceDate: Date
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(option.title)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.primaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(option.subtitle(from: referenceDate))
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 86)
            .padding(.horizontal, 8)
            .background(isSelected ? FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10) : FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .stroke(isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                    .background {
                        if isSelected {
                            Circle().fill(FactTrailTheme.aiAccent(for: colorScheme))
                        }
                    }
                    .frame(width: 17, height: 17)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
            }
        }
        .buttonStyle(HomePressButtonStyle())
    }
}

private struct AIInsightRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AIServiceStatusView: View {
    let mode: AIServiceMode

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.caption.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch mode {
        case .mock:
            return "exclamationmark.triangle.fill"
        case .backend:
            return "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch mode {
        case .mock:
            return .orange
        case .backend:
            return .green
        }
    }

    private var message: String {
        switch mode {
        case .mock:
            return "Using local mock responses. Real AI is not connected from this app build."
        case .backend(let url):
            return "Using backend at \(url.absoluteString)."
        }
    }
}

private struct AIAnalysisCard: View {
    let analysis: AIIncidentAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("I think I understand what happened.")
                    .font(.headline)

                if analysis.understandingSummary.isEmpty {
                    Text("I found enough information to organize this incident, but more details may make the record clearer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(analysis.understandingSummary, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text(item)
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            Divider()

            AIInsightRow(
                title: "Suggested Category",
                value: analysis.suggestedCategory.rawValue
            )

            AIInsightRow(
                title: "Why this category",
                value: analysis.categoryReason
            )

            if !analysis.missingInformation.isEmpty {
                AIInsightRow(
                    title: "Missing Information",
                    value: analysis.missingInformation.joined(separator: ", ")
                )
            }

            if !analysis.evidenceMentioned.isEmpty {
                AIInsightRow(
                    title: "Evidence Mentioned",
                    value: analysis.evidenceMentioned.joined(separator: ", ")
                )
            }

            if !analysis.patternTags.isEmpty {
                AIInsightRow(
                    title: "Possible Pattern Tags",
                    value: analysis.patternTags.map(\.displayName).joined(separator: ", ")
                )
            }

            Text(analysis.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .factTrailGlassCard()
    }
}

private struct AIFollowUpQuestionView: View {
    let question: AIFollowUpQuestion
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.priority.rawValue)
                .font(.caption.bold())
                .foregroundStyle(priorityColor)

            Text(question.question)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(question.whyItMatters)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Answer if known", text: $answer, axis: .vertical)
                .lineLimit(2...5)
        }
        .padding(.vertical, 4)
    }

    private var priorityColor: Color {
        switch question.priority {
        case .high:
            return .blue
        case .helpfulContext:
            return .secondary
        case .optional:
            return .secondary
        }
    }
}

#if DEBUG
private struct AIDebugSnapshotView: View {
    let snapshot: AIAnalysisDebugSnapshot

    var body: some View {
        DisclosureGroup("DEBUG: AI Pipeline") {
            VStack(alignment: .leading, spacing: 12) {
                DebugTextSection(title: "Structured Facts", values: snapshot.structuredFacts)
                DebugTextSection(title: "Detected Entities", values: snapshot.detectedEntities)
                DebugTextSection(title: "Detected Event Type", values: [snapshot.detectedEventType])
                DebugTextSection(title: "Detected Category", values: [snapshot.detectedCategory])
                DebugTextSection(title: "Category Confidence", values: [snapshot.categoryConfidence])
                DebugTextSection(title: "Evidence Detected", values: snapshot.evidenceDetected)
                DebugTextSection(title: "Missing Facts", values: snapshot.missingFacts)
                DebugTextSection(title: "Generated Questions", values: snapshot.generatedQuestions)
                DebugTextSection(title: "Pattern Tags", values: snapshot.patternTags)
            }
            .padding(.top, 8)
        }
        .font(.footnote)
    }
}

private struct DebugTextSection: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
            if values.isEmpty {
                Text("None")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text("• \(value)")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
#endif

private struct FinalDocumentationCard: View {
    let finalDocumentation: FinalDocumentationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Final Documentation Summary")
                .font(.headline)

            Text(finalDocumentation.summary)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            DocumentationCompletenessView(completeness: finalDocumentation.completeness)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DocumentationCompletenessView: View {
    let completeness: DocumentationCompleteness

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Documentation Completeness")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(completeness.score)%")
                    .font(.title3.bold())
            }

            Text(completeness.status)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if !completeness.completedItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Completed")
                        .font(.caption.bold())
                    ForEach(completeness.completedItems, id: \.self) { item in
                        Label(item, systemImage: "checkmark")
                            .font(.caption)
                    }
                }
            }

            if !completeness.missingItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Still Missing")
                        .font(.caption.bold())
                    ForEach(completeness.missingItems, id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct SummaryReviewView: View {
    let summaryDraft: IncidentSummaryDraft
    let onSave: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReviewSection(title: "Original Notes", text: summaryDraft.draft.originalNotes)

                if let analysis = summaryDraft.draft.aiAnalysis {
                    ReviewSection(
                        title: "AI Understanding",
                        text: analysis.understandingSummary.isEmpty ? "Not available" : analysis.understandingSummary.joined(separator: "\n")
                    )
                }

                ReviewSection(title: "Category", text: summaryDraft.draft.category.rawValue)

                if let analysis = summaryDraft.draft.aiAnalysis, !analysis.evidenceMentioned.isEmpty {
                    ReviewSection(title: "Evidence Mentioned", text: analysis.evidenceMentioned.joined(separator: ", "))
                }

                if !answeredGuidedQuestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Follow-Up Questions")
                            .font(.headline)
                        ForEach(Array(summaryDraft.followUpQuestions.enumerated()), id: \.offset) { index, question in
                            Text("\(index + 1). \(question)")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("User Responses")
                            .font(.headline)
                        ForEach(answeredGuidedQuestions) { answer in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(answer.question)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(answer.answer)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                if !summaryDraft.draft.evidenceTypes.isEmpty || !summaryDraft.draft.patternTags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        if !summaryDraft.draft.evidenceTypes.isEmpty {
                            ReviewChipSection(
                                title: "Evidence Types",
                                values: summaryDraft.draft.evidenceTypes.map(\.rawValue)
                            )
                        }

                        if !summaryDraft.draft.patternTags.isEmpty {
                            ReviewChipSection(
                                title: "Pattern Tags",
                                values: summaryDraft.draft.patternTags.map(\.displayName)
                            )
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                if !summaryDraft.draft.evidenceAttachments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attached Photos and Screenshots")
                            .font(.headline)
                        EvidenceAttachmentGrid(
                            attachments: summaryDraft.draft.evidenceAttachments,
                            onRemove: nil
                        )
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                }

                if let finalDocumentation = summaryDraft.draft.finalDocumentation {
                    FinalDocumentationCard(finalDocumentation: finalDocumentation)
                } else {
                    ReviewSection(
                        title: "Draft Summary",
                        text: "Generate a Final Documentation Summary to create a complete narrative from the original notes and guided responses."
                    )
                }

                VStack(spacing: 12) {
                    if let pdfURL {
                        ShareLink(
                            item: pdfURL,
                            subject: Text("Coparo Summary"),
                            message: Text("Coparo documentation summary")
                        ) {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FactTrailGlassButtonStyle())
                        .controlSize(.large)
                    } else if let pdfErrorMessage {
                        Text(pdfErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Preparing PDF...")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: onSave) {
                        Label("Save Incident", systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailPrimaryButtonStyle())
                    .controlSize(.large)

                    Button(action: onEdit) {
                        Label("Edit Entry", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailGlassButtonStyle())
                    .controlSize(.large)

                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailGlassButtonStyle())
                    .controlSize(.large)
                }
            }
            .padding(20)
        }
        .factTrailScreenBackground()
        .navigationTitle("Review Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            preparePDF()
        }
    }

    private func preparePDF() {
        do {
            pdfURL = try IncidentPDFExporter.makePDF(for: summaryDraft)
            pdfErrorMessage = nil
        } catch {
            pdfURL = nil
            pdfErrorMessage = "PDF could not be prepared on this device."
        }
    }

    private var answeredGuidedQuestions: [GuidedQuestionAnswer] {
        summaryDraft.draft.guidedAnswers.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

private struct ReviewChipSection: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(values.joined(separator: ", "))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct EvidenceAttachmentGrid: View {
    let attachments: [EvidenceAttachment]
    let onRemove: ((EvidenceAttachment) -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 92), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(attachments) { attachment in
                EvidenceAttachmentThumbnail(attachment: attachment, onRemove: onRemove)
            }
        }
    }
}

private struct EvidenceAttachmentThumbnail: View {
    let attachment: EvidenceAttachment
    let onRemove: ((EvidenceAttachment) -> Void)?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let uiImage = UIImage(data: attachment.data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 0.5)
            }

            if let onRemove {
                Button {
                    onRemove(attachment)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(4)
                .accessibilityLabel("Remove attachment")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attachment.fileName)
    }
}

private struct ReviewSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private enum TimelineDisplayStyle: String, CaseIterable, Identifiable {
    case branch = "Branch"
    case list = "List"
    case calendar = "Calendar"

    var id: String { rawValue }
}

private enum TimelineDensity: String, CaseIterable, Identifiable {
    case detailed = "Detailed"
    case compact = "Compact"

    var id: String { rawValue }
}

private enum TimelineCalendarMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"

    var id: String { rawValue }
}

private struct TimelineView: View {
    let incidents: [Incident]
    let exchangeRecords: [ExchangeRecord]
    let checkIns: [CheckIn]
    let linkedNotes: [LinkedNote]
    let attachmentsProvider: (String) -> [StoredDocument]
    let saveErrorMessage: String?
    let onEdit: (Incident) -> Void
    let onAddLinkedNote: (TimelineItem, String) -> Void
    let onDeleteAttachment: (StoredDocument) -> Void
    var onInsights: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedStyle: TimelineDisplayStyle = .branch
    @State private var density: TimelineDensity = .detailed
    @State private var calendarMode: TimelineCalendarMode = .month
    @State private var selectedDate = Date()
    @State private var expandedItemIDs: Set<String> = []
    @State private var relatedFilterSource: TimelineItem?
    @State private var itemForMoreInfo: TimelineItem?
    @State private var itemForNote: TimelineItem?
    @State private var noteDraft = ""
    @State private var previewAttachment: StoredDocument?
    @State private var actionMenuItem: TimelineItem?

    var body: some View {
        VStack(spacing: 0) {
            timelineHeader
            timelineControls
            pinnedLegendBar

            if timelineItems.isEmpty {
                ContentUnavailableView(
                    "No records saved",
                    systemImage: "calendar.badge.clock",
                    description: Text("Saved check-ins, exchanges, and entries will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let relatedFilterSource {
                            RelatedEntriesFilterBanner(source: relatedFilterSource, onClear: clearRelatedFilter)
                        }

                        if filteredTimelineItems.isEmpty {
                            TimelineEmptyState(
                                title: relatedFilterSource == nil ? "No matching records" : "No related entries yet",
                                message: emptyStateMessage
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 120)
                        } else {
                            switch selectedStyle {
                            case .branch:
                                BranchTimelineView(
                                    items: chronologicalItems,
                                    annotations: timelineAnnotations,
                                    density: density,
                                    expandedItemIDs: $expandedItemIDs,
                                    notesFor: notes(for:),
                                    attachmentsFor: attachments(for:),
                                    onEdit: onEdit,
                                    onAddNote: beginAddNote,
                                    onSeeRelated: showRelatedEntries,
                                    onMoreInfo: { itemForMoreInfo = $0 },
                                    onAttachmentTapped: { previewAttachment = $0 },
                                    onLongPress: presentActionMenu
                                )
                            case .list:
                                ListTimelineView(
                                    groupedItems: groupedItems,
                                    density: density,
                                    expandedItemIDs: $expandedItemIDs,
                                    notesFor: notes(for:),
                                    attachmentsFor: attachments(for:),
                                    onEdit: onEdit,
                                    onAddNote: beginAddNote,
                                    onSeeRelated: showRelatedEntries,
                                    onMoreInfo: { itemForMoreInfo = $0 },
                                    onAttachmentTapped: { previewAttachment = $0 },
                                    onLongPress: presentActionMenu
                                )
                            case .calendar:
                                CalendarTimelineView(
                                    items: filteredTimelineItems,
                                    mode: calendarMode,
                                    selectedDate: $selectedDate
                                )
                            }
                        }

                        if relatedFilterSource == nil && !filteredIncidents.isEmpty {
                            TimelineFullPDFShareButton(incidents: filteredIncidents)
                                .padding(.top, 4)
                        }

                        Color.clear.frame(height: 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            HomeBottomNavigation(
                activeTab: .timeline,
                onHome: { dismiss() },
                onTimeline: {},
                onInsights: onInsights
            )
        }
        .factTrailScreenBackground()
        .navigationTitle(selectedStyle == .calendar ? "Calendar" : "Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let message = saveErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
        .sheet(item: $itemForMoreInfo) { item in
            TimelineMoreInfoSheet(
                item: item,
                notes: notes(for: item),
                attachments: attachments(for: item),
                onEdit: onEdit,
                onAttachmentTapped: { document in
                    previewAttachment = document
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $itemForNote) { item in
            TimelineAddNoteSheet(
                item: item,
                noteText: $noteDraft,
                onCancel: {
                    itemForNote = nil
                    noteDraft = ""
                },
                onSave: {
                    saveNote(for: item)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $previewAttachment) { document in
            TimelineAttachmentPreviewSheet(
                document: document,
                onClose: { previewAttachment = nil },
                onDelete: {
                    onDeleteAttachment(document)
                    previewAttachment = nil
                }
            )
        }
        .overlay {
            if let item = actionMenuItem {
                TimelineActionMenu(
                    item: item,
                    canQuickEdit: item.editableIncident != nil,
                    onDismiss: dismissActionMenu,
                    onQuickEdit: {
                        if let incident = item.editableIncident {
                            onEdit(incident)
                        }
                    },
                    onAddNote: { beginAddNote(item) },
                    onSeeRelated: { showRelatedEntries(for: item) },
                    onMoreInfo: { itemForMoreInfo = item }
                )
                .transition(.opacity)
            }
        }
    }

    private func attachments(for item: TimelineItem) -> [StoredDocument] {
        attachmentsProvider(item.id)
    }


    private func presentActionMenu(for item: TimelineItem) {
        withAnimation(.easeOut(duration: 0.18)) {
            actionMenuItem = item
        }
    }

    private func dismissActionMenu() {
        withAnimation(.easeIn(duration: 0.15)) {
            actionMenuItem = nil
        }
    }


    private var timelineHeader: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 17, weight: .medium, design: .default))
            }
            .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))

            Spacer()

            Text(selectedStyle == .calendar ? "Calendar" : "Timeline")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Spacer()

            Color.clear
                .frame(width: 64, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var timelineControls: some View {
        HStack(spacing: 8) {
            TimelineSegmentedControl(
                selection: $selectedStyle,
                options: TimelineDisplayStyle.allCases
            )

            if selectedStyle == .calendar {
                TimelineSegmentedControl(
                    selection: $calendarMode,
                    options: TimelineCalendarMode.allCases
                )
            } else {
                TimelineSegmentedControl(
                    selection: $density,
                    options: TimelineDensity.allCases
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var pinnedLegendBar: some View {
        HStack(spacing: 0) {
            TimelineLegend()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background(alignment: .bottom) {
            VStack(spacing: 0) {
                FactTrailTheme.background(for: colorScheme)
                Rectangle()
                    .fill(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.35 : 0.25))
                    .frame(height: 0.5)
            }
        }
    }

    private var filteredIncidents: [Incident] {
        incidents
    }

    private var chronologicalItems: [TimelineItem] {
        filteredTimelineItems.sorted { $0.date < $1.date }
    }

    private var groupedItems: [(key: TimelineGroupKey, items: [TimelineItem])] {
        let grouped = Dictionary(grouping: filteredTimelineItems) { item in
            TimelineGroupKey(date: item.date)
        }

        return grouped
            .map { (key: $0.key, items: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.key.sortDate > $1.key.sortDate }
    }

    /// AI/heuristic pattern markers interleaved on the branch spine.
    private var timelineAnnotations: [TimelineAnnotation] {
        TimelineInsightEngine.analyze(entries: makeTimelineInputs(from: timelineItems)).annotations
    }

    private var timelineItems: [TimelineItem] {
        let incidentsByExchangeID = Dictionary(
            uniqueKeysWithValues: incidents.compactMap { incident -> (UUID, Incident)? in
                guard let exchangeRecordID = incident.exchangeRecordID else {
                    return nil
                }
                return (exchangeRecordID, incident)
            }
        )
        let exchangeItems = exchangeRecords.map { record in
            TimelineItem.exchangeRecord(record, incidentsByExchangeID[record.id])
        }
        let standaloneIncidentItems = incidents
            .filter { $0.exchangeRecordID == nil }
            .map(TimelineItem.incident)
        let checkInItems = checkIns.map(TimelineItem.checkIn)

        return (standaloneIncidentItems + exchangeItems + checkInItems)
            .sorted { $0.date > $1.date }
    }

    private var filteredTimelineItems: [TimelineItem] {
        // No search/category filtering — the prototype shows everything, with
        // "See related entries" (tag match) as the only filter.
        let baseItems = timelineItems

        guard let relatedFilterSource else {
            return baseItems
        }

        let sourceTags = Set(relatedFilterSource.tags)
        guard !sourceTags.isEmpty else {
            return []
        }

        return baseItems.filter { item in
            item.id != relatedFilterSource.id
            && !Set(item.tags).isDisjoint(with: sourceTags)
        }
    }

    private func beginAddNote(_ item: TimelineItem) {
        noteDraft = ""
        itemForNote = item
    }

    private func saveNote(for item: TimelineItem) {
        let trimmedNote = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else {
            return
        }

        onAddLinkedNote(item, trimmedNote)
        itemForNote = nil
        noteDraft = ""
    }

    private func notes(for item: TimelineItem) -> [LinkedNote] {
        linkedNotes
            .filter { $0.parentItemID == item.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func showRelatedEntries(for item: TimelineItem) {
        withAnimation(.snappy) {
            relatedFilterSource = item
            selectedStyle = .list
            density = .detailed
            expandedItemIDs.removeAll()
        }
    }

    private func clearRelatedFilter() {
        withAnimation(.snappy) {
            relatedFilterSource = nil
            expandedItemIDs.removeAll()
        }
    }

    private var emptyStateMessage: String {
        guard let relatedFilterSource else {
            return "Adjust search or filters to see more timeline records."
        }

        if relatedFilterSource.tags.isEmpty {
            return "This entry does not have tags yet. Related entries appear after items are tagged by timing, communication, compliance, or care concerns."
        }

        return "Related entries appear when other items share tags like timing, communication, compliance, or care concerns."
    }

}

private struct TimelineGroupKey: Hashable {
    let year: Int
    let month: Int
    let sortDate: Date

    init(date: Date) {
        let calendar = Calendar.current
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        sortDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date
    }

    var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: sortDate).uppercased()
    }
}

private struct TimelineSegmentedControl<Option>: View where Option: CaseIterable & Identifiable & RawRepresentable & Equatable, Option.RawValue == String {
    @Binding var selection: Option
    let options: [Option]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy) {
                        selection = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 12, weight: selection == option ? .semibold : .medium, design: .default))
                        .foregroundStyle(selection == option ? FactTrailTheme.primaryText(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 9)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(FactTrailTheme.surface(for: colorScheme))
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 6, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.28 : 0.36))
        )
    }
}

private struct TimelineLegend: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            legendItem("Entry", color: FactTrailTheme.primaryAction(for: colorScheme))
            legendItem("Check-in", color: FactTrailTheme.aiAccent(for: colorScheme))
            legendItem("Exchange", color: FactTrailTheme.primaryAction(for: colorScheme).opacity(0.72))
            legendItem("Document", color: .green)
        }
        .font(.system(size: 12, weight: .medium, design: .default))
        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .lineLimit(1)
        }
    }
}

private struct BranchTimelineView: View {
    let items: [TimelineItem]
    /// AI-detected pattern markers, interleaved chronologically on the spine.
    /// Empty until the AI analysis pass is wired up.
    var annotations: [TimelineAnnotation] = []
    let density: TimelineDensity
    @Binding var expandedItemIDs: Set<String>
    let notesFor: (TimelineItem) -> [LinkedNote]
    let attachmentsFor: (TimelineItem) -> [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    let onLongPress: (TimelineItem) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var containerWidth: CGFloat = 0

    private let gutterWidth: CGFloat = 40

    private var cardColumnWidth: CGFloat {
        guard containerWidth > gutterWidth else { return 150 }
        return max(min((containerWidth - gutterWidth) / 2, 240), 120)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(branchRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .year(let year):
                    TimelineYearPill(year: year)
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                case .month(let month):
                    TimelineMonthLabel(month: month)
                        .padding(.bottom, 14)
                case .item(let item, let index):
                    BranchTimelineRow(
                        item: item,
                        isLeft: index.isMultiple(of: 2),
                        density: density,
                        isExpanded: expandedItemIDs.contains(item.id),
                        notes: notesFor(item),
                        attachments: attachmentsFor(item),
                        cardColumnWidth: cardColumnWidth,
                        gutterWidth: gutterWidth,
                        onToggle: { toggle(item) },
                        onEdit: onEdit,
                        onAddNote: onAddNote,
                        onSeeRelated: onSeeRelated,
                        onMoreInfo: onMoreInfo,
                        onAttachmentTapped: onAttachmentTapped,
                        onLongPress: onLongPress
                    )
                    .padding(.bottom, rowBottomPadding(isExpanded: expandedItemIDs.contains(item.id)))
                case .annotation(let annotation):
                    TimelineAnnotationRow(
                        annotation: annotation,
                        cardColumnWidth: cardColumnWidth,
                        gutterWidth: gutterWidth
                    )
                    .padding(.bottom, 14)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        if containerWidth != proxy.size.width {
                            containerWidth = proxy.size.width
                        }
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        if containerWidth != newValue {
                            containerWidth = newValue
                        }
                    }
            }
        }
        .background(alignment: .top) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.65))
                    .frame(width: 1.6)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 20)
        }
    }

    private func rowBottomPadding(isExpanded: Bool) -> CGFloat {
        if isExpanded {
            return density == .compact ? 28 : 40
        }
        return density == .compact ? 16 : 22
    }

    private var branchRows: [BranchRow] {
        var rows: [BranchRow] = []
        var currentYear: Int?
        var currentMonth: Int?
        var itemIndex = 0
        var pendingAnnotations = annotations.sorted { $0.anchorDate < $1.anchorDate }

        for item in items {
            // Flush AI pattern annotations that belong before this entry.
            while let next = pendingAnnotations.first, next.anchorDate < item.date {
                rows.append(.annotation(next))
                pendingAnnotations.removeFirst()
            }

            let year = Calendar.current.component(.year, from: item.date)
            let month = Calendar.current.component(.month, from: item.date)
            if currentYear != year {
                rows.append(.year(year))
                currentYear = year
                currentMonth = nil
            }
            if currentMonth != month {
                rows.append(.month(TimelineGroupKey(date: item.date).monthLabel))
                currentMonth = month
            }
            rows.append(.item(item, itemIndex))
            itemIndex += 1
        }

        rows.append(contentsOf: pendingAnnotations.map { .annotation($0) })
        return rows
    }

    private func toggle(_ item: TimelineItem) {
        withAnimation(.snappy) {
            if expandedItemIDs.contains(item.id) {
                expandedItemIDs.remove(item.id)
            } else {
                expandedItemIDs.insert(item.id)
            }
        }
    }
}

private enum BranchRow {
    case year(Int)
    case month(String)
    case item(TimelineItem, Int)
    case annotation(TimelineAnnotation)
}

private struct TimelineAnnotationRow: View {
    let annotation: TimelineAnnotation
    let cardColumnWidth: CGFloat
    let gutterWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private let flagAmber = Color(hex: 0xD97706)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear
                .frame(width: cardColumnWidth, height: 1)

            // Amber flag centered on the spine.
            Circle()
                .fill(flagAmber.opacity(0.15))
                .overlay {
                    Circle()
                        .strokeBorder(flagAmber, lineWidth: 1.5)
                }
                .overlay {
                    Image(systemName: "flag")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(flagAmber)
                }
                .frame(width: 22, height: 22)
                .frame(width: gutterWidth, alignment: .center)

            Text(annotation.text)
                .font(.system(size: 11, weight: .regular, design: .default))
                .italic()
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .multilineTextAlignment(.leading)
                .frame(width: cardColumnWidth, alignment: .leading)
                .padding(.top, 2)
        }
    }
}

private struct BranchTimelineRow: View {
    let item: TimelineItem
    let isLeft: Bool
    let density: TimelineDensity
    let isExpanded: Bool
    let notes: [LinkedNote]
    let attachments: [StoredDocument]
    let cardColumnWidth: CGFloat
    let gutterWidth: CGFloat
    let onToggle: () -> Void
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    let onLongPress: (TimelineItem) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftColumn
            spineColumn
            rightColumn
        }
        .frame(minHeight: collapsedMinHeight, alignment: .top)
    }

    @ViewBuilder
    private var leftColumn: some View {
        if isLeft {
            cardView
                .frame(width: cardColumnWidth, alignment: .trailing)
        } else {
            Color.clear
                .frame(width: cardColumnWidth, height: 1)
        }
    }

    @ViewBuilder
    private var rightColumn: some View {
        if !isLeft {
            cardView
                .frame(width: cardColumnWidth, alignment: .leading)
        } else {
            Color.clear
                .frame(width: cardColumnWidth, height: 1)
        }
    }

    private var spineColumn: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(item.timelineColor(for: colorScheme).opacity(0.55))
                .frame(width: 12, height: 1.3)
                .padding(.top, 30)
                .offset(x: isLeft ? -15 : 15)

            // Prototype node: filled colored dot, thin surface gap, colored outer ring.
            Circle()
                .fill(item.timelineColor(for: colorScheme))
                .frame(width: 9, height: 9)
                .padding(2.5)
                .background(Circle().fill(FactTrailTheme.surface(for: colorScheme)))
                .overlay {
                    Circle()
                        .strokeBorder(item.timelineColor(for: colorScheme), lineWidth: 1.5)
                }
                .padding(.top, 24)
        }
        .frame(width: gutterWidth, alignment: .top)
    }

    private var cardView: some View {
        TimelineItemCard(
            item: item,
            density: density,
            isExpanded: isExpanded,
            notes: notes,
            attachments: attachments,
            onToggle: onToggle,
            onEdit: onEdit,
            onAddNote: onAddNote,
            onSeeRelated: onSeeRelated,
            onMoreInfo: onMoreInfo,
            onAttachmentTapped: onAttachmentTapped
        )
        .timelineActions(item: item, onLongPress: onLongPress)
    }

    private var collapsedMinHeight: CGFloat {
        density == .compact ? 72 : 88
    }
}

private struct ListTimelineView: View {
    let groupedItems: [(key: TimelineGroupKey, items: [TimelineItem])]
    let density: TimelineDensity
    @Binding var expandedItemIDs: Set<String>
    let notesFor: (TimelineItem) -> [LinkedNote]
    let attachmentsFor: (TimelineItem) -> [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    let onLongPress: (TimelineItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupedItems, id: \.key) { group in
                VStack(alignment: .leading, spacing: 10) {
                    TimelineYearPill(year: group.key.year)
                    TimelineMonthLabel(month: group.key.monthLabel)
                    ForEach(group.items) { item in
                        TimelineItemCard(
                            item: item,
                            density: density,
                            isExpanded: expandedItemIDs.contains(item.id),
                            notes: notesFor(item),
                            attachments: attachmentsFor(item),
                            onToggle: { toggle(item) },
                            onEdit: onEdit,
                            onAddNote: onAddNote,
                            onSeeRelated: onSeeRelated,
                            onMoreInfo: onMoreInfo,
                            onAttachmentTapped: onAttachmentTapped
                        )
                        .timelineActions(item: item, onLongPress: onLongPress)
                    }
                }
            }
        }
    }

    private func toggle(_ item: TimelineItem) {
        withAnimation(.snappy) {
            if expandedItemIDs.contains(item.id) {
                expandedItemIDs.remove(item.id)
            } else {
                expandedItemIDs.insert(item.id)
            }
        }
    }
}

private struct TimelineItemCard: View {
    let item: TimelineItem
    let density: TimelineDensity
    let isExpanded: Bool
    let notes: [LinkedNote]
    let attachments: [StoredDocument]
    let onToggle: () -> Void
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: density == .compact ? 7 : 9) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(item.timelineColor(for: colorScheme))
                        .frame(width: 8, height: 8)
                    // Header sized to the prototype's ~10px so the category label and the
                    // timestamp both fit on one line even in the narrow branch card (where the
                    // time would otherwise wrap to "Mon / 9:13 / PM"). minimumScaleFactor is a
                    // safety net for the tightest widths.
                    Text(item.typeLabel.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .tracking(0.6)
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Spacer(minLength: 6)
                    Text(DateFormatter.factTrailCompactDateTime.string(from: item.date))
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                }

                Text(item.title)
                    .font(.system(size: density == .compact ? 15 : 16, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .lineLimit(density == .compact ? 2 : 3)

                if density == .detailed {
                    Text(item.summary)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .lineLimit(isExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TimelineBadges(item: item, attachmentCount: attachments.count)

                if density == .detailed, !item.tags.isEmpty {
                    EntryTagChips(tags: item.tags)
                }

                if isExpanded {
                    Divider()
                        .padding(.vertical, 2)
                    TimelineExpandedDetails(
                        item: item,
                        notes: notes,
                        attachments: attachments,
                        onEdit: onEdit,
                        onAddNote: onAddNote,
                        onSeeRelated: onSeeRelated,
                        onMoreInfo: onMoreInfo,
                        onAttachmentTapped: onAttachmentTapped
                    )
                }
            }
            .padding(density == .compact ? 12 : 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .factTrailGlassCard(cornerRadius: 14)
        }
        .buttonStyle(FactTrailGlassCardButtonStyle())
    }
}

private struct TimelineBadges: View {
    let item: TimelineItem
    let attachmentCount: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let combinedAttachments = item.attachmentCount + attachmentCount
        HStack(spacing: 7) {
            if !item.locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                badge("Location", systemImage: "mappin.and.ellipse")
            }
            if combinedAttachments > 0 {
                badge("\(combinedAttachments)", systemImage: "paperclip")
            }
            if item.isFlagged {
                badge("Flagged", systemImage: "flag")
            }
        }
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.78))
            )
    }
}

private struct TimelineExpandedDetails: View {
    let item: TimelineItem
    let notes: [LinkedNote]
    let attachments: [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineDetailSection(title: "Details", text: item.summary)

            if !item.locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TimelineDetailSection(title: "Location", text: item.locationText)
            }

            TimelineDetailRow(label: "Occurred", value: DateFormatter.factTrailDateTime.string(from: item.date))

            if item.attachmentCount > 0 {
                TimelineDetailRow(label: "Original evidence", value: "\(item.attachmentCount) file\(item.attachmentCount == 1 ? "" : "s")")
            }

            TimelineAttachmentsSection(
                attachments: attachments,
                onAttachmentTapped: onAttachmentTapped
            )

            if !notes.isEmpty {
                TimelineNotesInlineSection(notes: notes)
            }

            TimelineStatusChips(item: item)

            Button {
                onAddNote(item)
            } label: {
                Text("Add note")
                    .font(.system(size: 12.5, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule().fill(FactTrailTheme.surface(for: colorScheme))
                    )
                    .overlay {
                        Capsule().stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TimelineStatusChips: View {
    let item: TimelineItem
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            chip(text: item.typeLabel, tone: .neutral)

            if item.isFlagged {
                chip(text: "Flagged", tone: .warning)
            }
        }
    }

    private enum ChipTone {
        case neutral, warning
    }

    private func chip(text: String, tone: ChipTone) -> some View {
        let background: Color = {
            switch tone {
            case .neutral:
                return FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.75)
            case .warning:
                return Color.orange.opacity(colorScheme == .dark ? 0.24 : 0.16)
            }
        }()
        let foreground: Color = {
            switch tone {
            case .neutral:
                return FactTrailTheme.secondaryText(for: colorScheme)
            case .warning:
                return Color.orange
            }
        }()

        return Text(text)
            .font(.system(size: 11, weight: .medium, design: .default))
            .foregroundStyle(foreground)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(background))
    }
}

private struct RelatedEntriesFilterBanner: View {
    let source: TimelineItem
    let onClear: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Related entries")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("Showing entries related to: \(source.title)")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .lineLimit(2)
                    if source.tags.isEmpty {
                        Text("This entry does not have tags yet.")
                            .font(.system(size: 11.5, weight: .medium, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                }
                Spacer()
                Button("Clear") {
                    onClear()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            }

            EntryTagChips(tags: source.tags)
        }
        .padding(14)
        .factTrailGlassCard(cornerRadius: 14)
    }
}

private struct TimelineEmptyState: View {
    let title: String
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
        }
    }
}

private struct EntryTagChips: View {
    let tags: [EntryTag]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !tags.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(tags) { tag in
                    Text(tag.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
                        .lineLimit(1)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(FactTrailTheme.primaryAction(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.10))
                        )
                }
            }
        }
    }
}

private struct TimelineMoreInfoSheet: View {
    let item: TimelineItem
    let notes: [LinkedNote]
    let attachments: [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        infoChip(item.typeLabel)
                        infoChip(DateFormatter.factTrailDateTime.string(from: item.date))
                    }
                }

                TimelineDetailSection(title: "Details", text: item.summary)
                TimelineDetailSection(title: "Location", text: item.locationText)

                if item.attachmentCount > 0 {
                    TimelineDetailRow(label: "Original evidence", value: "\(item.attachmentCount) file\(item.attachmentCount == 1 ? "" : "s")")
                }

                if item.isFlagged {
                    Label("Flagged", systemImage: "flag")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                EntryTagChips(tags: item.tags)

                TimelineAttachmentsSection(
                    attachments: attachments,
                    onAttachmentTapped: onAttachmentTapped
                )

                if !notes.isEmpty {
                    TimelineNotesInlineSection(notes: notes)
                }

                if let incident = item.editableIncident {
                    Button {
                        dismiss()
                        onEdit(incident)
                    } label: {
                        Label("Quick edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailGlassButtonStyle())
                }

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
            }
            .padding(20)
        }
        .factTrailScreenBackground()
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Capsule()
                    .fill(FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.78))
            )
    }
}

private struct TimelineAddNoteSheet: View {
    let item: TimelineItem
    @Binding var noteText: String
    let onCancel: () -> Void
    let onSave: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add note")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Text(item.title)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }

            TextEditor(text: $noteText)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .frame(minHeight: 140)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FactTrailTheme.surface(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                )

            Button {
                onSave()
            } label: {
                Text("Save note")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailGlassButtonStyle())
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Cancel") {
                onCancel()
            }
            .font(.system(size: 15, weight: .semibold, design: .default))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .factTrailScreenBackground()
    }
}

private extension View {
    func timelineActions(item: TimelineItem, onLongPress: @escaping (TimelineItem) -> Void) -> some View {
        self.simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress(item)
                }
        )
    }
}

private struct TimelineYearPill: View {
    let year: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(verbatim: String(year))
            .font(.system(size: 13, weight: .bold, design: .default))
            .tracking(2)
            .foregroundStyle(FactTrailTheme.background(for: colorScheme))
            .padding(.vertical, 7)
            .padding(.horizontal, 16)
            .background(Capsule().fill(FactTrailTheme.primaryText(for: colorScheme)))
            .frame(maxWidth: .infinity)
    }
}

private struct TimelineMonthLabel: View {
    let month: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(month)
            .font(.system(size: 13, weight: .bold, design: .default))
            .tracking(2.4)
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            .frame(maxWidth: .infinity)
    }
}

private struct CalendarTimelineView: View {
    let items: [TimelineItem]
    let mode: TimelineCalendarMode
    @Binding var selectedDate: Date
    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthHeader

            HStack(spacing: 14) {
                calendarLegend("Your days", color: FactTrailTheme.primaryAction(for: colorScheme).opacity(0.20))
                calendarLegend("Co-parent's days", color: FactTrailTheme.primaryAction(for: colorScheme).opacity(0.12))
                calendarLegend("Exchange", color: FactTrailTheme.aiAccent(for: colorScheme).opacity(0.24), stroked: true)
            }
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            if mode == .month {
                monthGrid
            } else {
                weekGrid
            }

            selectedDayCard
        }
        .onAppear {
            visibleMonth = selectedDate
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftVisibleMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(FactTrailGlassCardButtonStyle())

            Spacer()

            Text(monthTitle)
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Spacer()

            Button {
                shiftVisibleMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(FactTrailGlassCardButtonStyle())
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(shortWeekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 12, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(monthDays, id: \.self) { date in
                    CalendarDayCell(
                        date: date,
                        visibleMonth: visibleMonth,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        items: items(on: date),
                        isExchangeDay: isExchangeDay(date)
                    ) {
                        selectedDate = date
                    }
                }
            }
        }
    }

    private var weekGrid: some View {
        VStack(spacing: 6) {
            ForEach(weekDays, id: \.self) { date in
                Button {
                    selectedDate = date
                } label: {
                    HStack(spacing: 12) {
                        VStack {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.bold))
                            Text(date.formatted(.dateTime.day()))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? .white : FactTrailTheme.primaryText(for: colorScheme))
                        .frame(width: 46)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Calendar.current.isDate(date, inSameDayAs: selectedDate) ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.border(for: colorScheme).opacity(0.25))
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            let dayItems = items(on: date)
                            if dayItems.isEmpty {
                                Text("No entries")
                                    .font(.caption)
                                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            } else {
                                ForEach(dayItems.prefix(3)) { item in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(item.timelineColor(for: colorScheme))
                                            .frame(width: 7, height: 7)
                                        Text(item.title)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedDayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.system(size: 18, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Text(isExchangeDay(selectedDate) ? "Exchange day" : "Parenting day")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }
            .padding(14)

            Divider()

            let dayItems = items(on: selectedDate)
            if dayItems.isEmpty {
                Text("No records logged on this day.")
                    .font(.footnote)
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .padding(14)
            } else {
                ForEach(dayItems) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.timelineColor(for: colorScheme))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Text("\(item.typeLabel) · \(DateFormatter.factTrailCompactDateTime.string(from: item.date))")
                                .font(.caption)
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
                    }
                    .padding(14)
                    Divider()
                }
            }
        }
        .factTrailGlassCard(cornerRadius: 16)
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    private var shortWeekdays: [String] {
        Calendar.current.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
    }

    private var monthDays: [Date] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [Date] = []
        var date = monthFirstWeek.start
        while date < monthLastWeek.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)
        }
        return days
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfMonth, for: selectedDate) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    private func items(on date: Date) -> [TimelineItem] {
        items
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    private func shiftVisibleMonth(by value: Int) {
        visibleMonth = Calendar.current.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
        selectedDate = visibleMonth
    }

    private func isExchangeDay(_ date: Date) -> Bool {
        items(on: date).contains {
            if case .exchangeRecord = $0 {
                return true
            }
            return false
        }
    }

    private func calendarLegend(_ title: String, color: Color, stroked: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4)
                .fill(stroked ? .clear : color)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(stroked ? FactTrailTheme.aiAccent(for: colorScheme) : color, lineWidth: 1.4)
                }
                .frame(width: 12, height: 12)
            Text(title)
                .lineLimit(1)
        }
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let visibleMonth: Date
    let isSelected: Bool
    let items: [TimelineItem]
    let isExchangeDay: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(isSelected ? .white : dayTextColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : .clear)
                    )
                    .overlay {
                        if isExchangeDay && !isSelected {
                            Circle()
                                .stroke(FactTrailTheme.aiAccent(for: colorScheme), lineWidth: 2)
                        }
                    }

                HStack(spacing: 2) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(item.timelineColor(for: colorScheme))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dayBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private var dayTextColor: Color {
        Calendar.current.isDate(date, equalTo: visibleMonth, toGranularity: .month)
        ? FactTrailTheme.primaryText(for: colorScheme)
        : FactTrailTheme.mutedText(for: colorScheme).opacity(0.42)
    }

    private var dayBackground: Color {
        guard Calendar.current.isDate(date, equalTo: visibleMonth, toGranularity: .month) else {
            return .clear
        }
        return FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.34)
    }
}

private extension TimelineItem {
    func timelineColor(for colorScheme: ColorScheme) -> Color {
        switch self {
        case .incident:
            return FactTrailTheme.primaryAction(for: colorScheme)
        case .exchangeRecord:
            return FactTrailTheme.primaryAction(for: colorScheme).opacity(0.76)
        case .checkIn:
            return FactTrailTheme.aiAccent(for: colorScheme)
        }
    }
}

// MARK: - Insights (view layer)

private func insightAccent(_ type: InsightType, _ colorScheme: ColorScheme) -> Color {
    type == .concern ? Color(hex: 0xD97706) : FactTrailTheme.aiAccent(for: colorScheme)
}

private extension EntryKind {
    var displayColor: Color {
        switch self {
        case .entry: return Color(hex: 0x2F5D8C)
        case .checkin: return Color(hex: 0x4F8F8B)
        case .exchange: return Color(hex: 0x7B6FAB)
        case .document: return Color(hex: 0x059669)
        case .flag: return Color(hex: 0xD97706)
        }
    }
}

private struct InsightsScreenView: View {
    let entries: [TimelineEntryInput]
    let aiService: any AIService
    let onHome: () -> Void
    let onTimeline: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var insights: [Insight] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var dragOffset: CGFloat = 0
    @State private var expandedHistoryID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            HomeBottomNavigation(
                activeTab: .insights,
                onHome: { dismiss() },
                onTimeline: onTimeline,
                onInsights: {}
            )
        }
        .factTrailScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !loaded else { return }
            let result = try? await aiService.analyzeTimeline(entries: entries)
            insights = result?.insights ?? []
            index = 0
            loaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            Spacer()
            ProgressView().tint(FactTrailTheme.aiAccent(for: colorScheme))
            Spacer()
        } else if insights.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    introBlock
                    cardStack
                    navDots
                    historySection
                    Color.clear.frame(height: 12)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 17, weight: .medium, design: .default))
            }
            .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))

            Spacer()
            Text("Insights")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Spacer()
            Color.clear.frame(width: 64, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LocationPulseDot(color: FactTrailTheme.aiAccent(for: colorScheme))
                Text("BASED ON YOUR RECORDS")
                    .font(.system(size: 10.5, weight: .semibold, design: .default))
                    .tracking(0.8)
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            Text("We looked over what's been logged and noticed a few consistencies worth your attention — including some of your own.")
                .font(.system(size: 13.5, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(insights.count) pattern\(insights.count == 1 ? "" : "s") found")
                    .font(.system(size: 11.5, weight: .semibold, design: .default))
            }
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            .padding(.vertical, 4)
            .padding(.horizontal, 11)
            .background(
                Capsule().fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.09))
                    .overlay { Capsule().strokeBorder(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.2), lineWidth: 1) }
            )
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var cardStack: some View {
        ZStack {
            ForEach(visiblePositions.reversed(), id: \.self) { p in
                let insight = insights[index + p]
                InsightCardView(insight: insight, onSupportTap: onTimeline)
                    .scaleEffect(p == 0 ? 1 : (p == 1 ? 0.97 : 0.94))
                    .offset(y: p == 0 ? 0 : (p == 1 ? 8 : 16))
                    .opacity(p == 0 ? 1 : (p == 1 ? 0.85 : 0.6))
                    .offset(x: p == 0 ? dragOffset : 0)
                    .rotationEffect(.degrees(p == 0 ? Double(dragOffset / 20) : 0))
                    .zIndex(Double(3 - p))
                    .gesture(p == 0 ? dragGesture : nil)
            }
        }
        .frame(height: 400)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var visiblePositions: [Int] {
        (0..<3).filter { index + $0 < insights.count }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                let w = value.translation.width
                if w < -threshold && index < insights.count - 1 {
                    fling(to: -700, then: 1)
                } else if w > threshold && index > 0 {
                    fling(to: 700, then: -1)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { dragOffset = 0 }
                }
            }
    }

    private func fling(to offset: CGFloat, then delta: Int) {
        withAnimation(.easeOut(duration: 0.22)) { dragOffset = offset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            index += delta
            dragOffset = 0
        }
    }

    private var navDots: some View {
        HStack(spacing: 6) {
            ForEach(insights.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.border(for: colorScheme))
                    .frame(width: i == index ? 16 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALL PATTERNS")
                .font(.system(size: 10.5, weight: .semibold, design: .default))
                .tracking(0.8)
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .padding(.leading, 2)

            ForEach(insights) { insight in
                InsightHistoryRow(
                    insight: insight,
                    isOpen: expandedHistoryID == insight.id,
                    onToggle: {
                        withAnimation(.easeOut(duration: 0.25)) {
                            expandedHistoryID = expandedHistoryID == insight.id ? nil : insight.id
                        }
                    },
                    onView: onTimeline
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10))
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
            .frame(width: 56, height: 56)
            .padding(.bottom, 18)
            Text("Still watching.")
                .font(.system(size: 16, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 8)
            Text("As you log more, we'll surface patterns worth your attention here.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InsightCardView: View {
    let insight: Insight
    let onSupportTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { insightAccent(insight.type, colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.14))
                    Image(systemName: insight.iconSystemName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(accent)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                    Text(insight.headline)
                        .font(.system(size: 16.5, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 14)

            Text(insight.body)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)

            insightVisual
                .padding(.bottom, insightHasVisual ? 16 : 0)

            Text("SUPPORTING ENTRIES")
                .font(.system(size: 10.5, weight: .semibold, design: .default))
                .tracking(0.6)
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                ForEach(insight.supporting) { s in
                    Button(action: onSupportTap) {
                        HStack(spacing: 8) {
                            Circle().fill(s.kind.displayColor).frame(width: 7, height: 7)
                            Text(s.text)
                                .font(.system(size: 11.5, weight: .medium, design: .default))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(s.date)
                                .font(.system(size: 10.5, weight: .regular, design: .default))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(FactTrailTheme.border(for: colorScheme).opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)

            Rectangle()
                .fill(FactTrailTheme.border(for: colorScheme))
                .frame(height: 1)
                .padding(.top, 12)
                .padding(.bottom, 10)
            Text("Not a legal conclusion — see the full pattern below.")
                .font(.system(size: 10, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .factTrailGlassCard(cornerRadius: 20)
    }

    private var insightHasVisual: Bool {
        if case .none = insight.visual { return false }
        return true
    }

    @ViewBuilder
    private var insightVisual: some View {
        switch insight.visual {
        case .strip(let dates):
            InsightStripView(dates: dates, color: accent)
        case .tally(let values, let labels):
            InsightTallyView(values: values, labels: labels, color: accent)
        case .none:
            EmptyView()
        }
    }
}

private struct InsightStripView: View {
    let dates: [String]
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHEN IT HAPPENED")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.5)
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(FactTrailTheme.border(for: colorScheme))
                        .frame(height: 3)
                        .frame(maxHeight: .infinity)
                    ForEach(dates.indices, id: \.self) { i in
                        let pct = dates.count == 1 ? 0.5 : CGFloat(i) / CGFloat(dates.count - 1)
                        Circle()
                            .fill(color)
                            .frame(width: 10, height: 10)
                            .overlay { Circle().strokeBorder(FactTrailTheme.surface(for: colorScheme), lineWidth: 2) }
                            .position(x: max(5, min(geo.size.width - 5, pct * geo.size.width)), y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 12)

            HStack {
                Text(dates.first ?? "")
                Spacer()
                Text(dates.last ?? "")
            }
            .font(.system(size: 9.5, weight: .regular, design: .default))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        }
    }
}

private struct InsightTallyView: View {
    let values: [Int]
    let labels: [String]
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let maxValue = max(values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text("BY MONTH")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.5)
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(values.indices, id: \.self) { i in
                    let ratio = max(CGFloat(values[i]) / CGFloat(maxValue), 0.12)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(values[i] > 0 ? color : color.opacity(0.16))
                        .frame(maxWidth: .infinity)
                        .frame(height: 46 * ratio)
                }
            }
            .frame(height: 46, alignment: .bottom)

            HStack(spacing: 5) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.system(size: 8.5, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct InsightHistoryRow: View {
    let insight: Insight
    let isOpen: Bool
    let onToggle: () -> Void
    let onView: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var dotColor: Color { insightAccent(insight.type, colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.headline)
                            .font(.system(size: 12.5, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                        Text("First seen \(insight.firstSeen) · Last seen \(insight.lastSeen)")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    Spacer(minLength: 6)
                    Text("\(insight.occurrences)×")
                        .font(.system(size: 10.5, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(FactTrailTheme.border(for: colorScheme).opacity(0.5)))
                }
                .padding(10)
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 10) {
                    insightVisual
                    Button(action: onView) {
                        Text("View entries in timeline")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(9)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.08))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.3), lineWidth: 1)
                                    }
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FactTrailTheme.border(for: colorScheme).opacity(0.22))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var insightVisual: some View {
        let accent = insightAccent(insight.type, colorScheme)
        switch insight.visual {
        case .strip(let dates):
            InsightStripView(dates: dates, color: accent)
        case .tally(let values, let labels):
            InsightTallyView(values: values, labels: labels, color: accent)
        case .none:
            Text("No new entries recently — last one was \(insight.lastSeen).")
                .font(.system(size: 10.5, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        }
    }
}

private struct CheckInTimelineCardView: View {
    let checkIn: CheckIn
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Check in")
                    .font(.headline)
                Spacer()
                Text(DateFormatter.factTrailDateTime.string(from: checkIn.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label(checkIn.displayLabel, systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))

            let address = checkIn.address.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(address.isEmpty ? "Location and time saved." : address)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !checkIn.followUpCompleted {
                Label("Follow-up available", systemImage: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .factTrailGlassCard()
    }
}

private struct ExchangeRecordCardView: View {
    let record: ExchangeRecord
    let attachedIncident: Incident?
    let onEditIncident: (Incident) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Exchange Record")
                    .font(.headline)
                Spacer()
                Text(DateFormatter.factTrailDateTime.string(from: record.exchangeDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(record.role.rawValue, systemImage: "person.2")
                Spacer(minLength: 8)
                Label(record.timingDescription, systemImage: record.timing.statusIcon)
                    .foregroundStyle(record.timing == .onTime ? .green : .orange)
            }
            .font(.subheadline)

            if !record.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label(record.address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let attachedIncident {
                Divider()
                Label("Expanded Incident Attached", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)

                Text(attachedIncidentPreview(attachedIncident))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button {
                    onEditIncident(attachedIncident)
                } label: {
                    Label("Edit Attached Incident", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
            }
        }
        .padding()
        .factTrailGlassCard()
    }

    private func attachedIncidentPreview(_ incident: Incident) -> String {
        let finalSummary = incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalSummary.isEmpty {
            return finalSummary
        }

        return incident.originalNotes
    }
}

private struct IncidentCardView: View {
    let incident: Incident
    let isExpanded: Bool
    let onToggle: () -> Void
    let onEdit: (Incident) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(incident.category)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(DateFormatter.factTrailDateTime.string(from: incident.incidentDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text(summaryPreview)
                        .font(.body)
                        .lineLimit(isExpanded ? nil : 4)
                        .foregroundStyle(.primary)

                    if hasEvidence {
                        Label(evidenceLabel, systemImage: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(FactTrailGlassCardButtonStyle())

            if isExpanded {
                Divider()
                IncidentExpandedDetailsView(incident: incident, onEdit: onEdit)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .factTrailGlassCard()
    }

    private var summaryPreview: String {
        let finalSummary = incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalSummary.isEmpty {
            return finalSummary
        }

        return incident.neutralSummary
            .components(separatedBy: .newlines)
            .first { $0.hasPrefix("Summary:") }?
            .replacingOccurrences(of: "Summary: ", with: "")
        ?? incident.neutralSummary
    }

    private var hasEvidence: Bool {
        !incident.evidenceNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !incident.evidenceAttachments.isEmpty
    }

    private var evidenceLabel: String {
        if incident.evidenceAttachments.isEmpty {
            return "Evidence notes added"
        }

        let attachmentText = "\(incident.evidenceAttachments.count) attachment\(incident.evidenceAttachments.count == 1 ? "" : "s")"
        let hasNotes = !incident.evidenceNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasNotes ? "Evidence notes and \(attachmentText)" : attachmentText
    }
}

private struct IncidentExpandedDetailsView: View {
    let incident: Incident
    let onEdit: (Incident) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineDetailSection(title: "Original Notes", text: incident.originalNotes)

            if let analysis = incident.aiAnalysis {
                TimelineDetailSection(
                    title: "AI Understanding",
                    text: analysis.understandingSummary.isEmpty ? "Not available" : analysis.understandingSummary.joined(separator: "\n")
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                TimelineDetailRow(label: "Category", value: incident.category)
                TimelineDetailRow(label: "People", value: incident.peopleInvolved)
                TimelineDetailRow(label: "Location", value: incident.location)
                TimelineDetailRow(label: "Child involved", value: incident.childInvolved ? "Yes" : "No")
                TimelineDetailRow(label: "Evidence notes", value: incident.evidenceNotes)
            }

            if let analysis = incident.aiAnalysis, !analysis.evidenceMentioned.isEmpty {
                TimelineDetailSection(
                    title: "Evidence Mentioned",
                    text: analysis.evidenceMentioned.joined(separator: ", ")
                )
            }

            if !incident.patternTags.isEmpty {
                TimelineDetailSection(
                    title: "Pattern Tags",
                    text: incident.patternTags.map(\.displayName).joined(separator: ", ")
                )
            }

            if !incident.followUpQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Follow-Up Questions")
                        .font(.subheadline.bold())
                    ForEach(Array(incident.followUpQuestions.enumerated()), id: \.offset) { index, question in
                        Text("\(index + 1). \(question)")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !answeredGuidedQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("User Responses")
                        .font(.subheadline.bold())
                    ForEach(answeredGuidedQuestions) { answer in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(answer.question)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(answer.answer)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !incident.evidenceAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attached Photos and Screenshots")
                        .font(.subheadline.bold())
                    EvidenceAttachmentGrid(attachments: incident.evidenceAttachments, onRemove: nil)
                }
            }

            if !incident.finalDocumentationSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TimelineDetailSection(title: "Final Documentation Summary", text: incident.finalDocumentationSummary)
            }

            if let completeness = incident.documentationCompleteness {
                DocumentationCompletenessView(completeness: completeness)
                    .padding()
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }

            TimelinePDFShareButton(incident: incident)

            Button {
                onEdit(incident)
            } label: {
                Label("Edit Incident", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private var answeredGuidedQuestions: [GuidedQuestionAnswer] {
        incident.guidedAnswers.filter {
            !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

private struct TimelineDetailSection: View {
    let title: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text(displayValue)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayValue: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not specified" : trimmed
    }
}

private struct TimelineDetailRow: View {
    let label: String
    let value: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            Text(displayValue)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not specified" : trimmed
    }
}

private struct TimelineNotesInlineSection: View {
    let notes: [LinkedNote]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Text("\(notes.count)")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(
                        Capsule()
                            .fill(FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.78))
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.text)
                            .font(.system(size: 12.5, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(DateFormatter.factTrailCompactDateTime.string(from: note.createdAt))
                            .font(.system(size: 10.5, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(FactTrailTheme.aiSoftBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.22), lineWidth: 1)
                    }
                }
            }
        }
    }
}

private struct TimelineAttachmentsSection: View {
    let attachments: [StoredDocument]
    let onAttachmentTapped: (StoredDocument) -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    }

    var body: some View {
        // Only show the Attachments section when the entry actually has attachments.
        // Attachments are added when logging an entry, not from the timeline, so there
        // are no "add screenshot / add photo" tiles here — only thumbnails of what exists.
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Attachments")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("\(attachments.count)")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(
                            Capsule().fill(FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.78))
                        )
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(attachments) { attachment in
                        TimelineAttachmentThumbnailTile(document: attachment)
                            .onTapGesture {
                                onAttachmentTapped(attachment)
                            }
                    }
                }
            }
        }
    }
}

private struct TimelineAttachmentThumbnailTile: View {
    let document: StoredDocument
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.75))
        )
    }

    private var label: String {
        if document.category == .screenshot {
            return "Screenshot"
        }
        if document.fileType == .image {
            return "Photo"
        }
        return document.category.displayName
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = document.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if document.fileType == .image, let url = document.localFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
                Image(systemName: document.fileType.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }
        }
    }
}

private struct TimelineActionMenu: View {
    let item: TimelineItem
    let canQuickEdit: Bool
    let onDismiss: () -> Void
    let onQuickEdit: () -> Void
    let onAddNote: () -> Void
    let onSeeRelated: () -> Void
    let onMoreInfo: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                if canQuickEdit {
                    row(icon: "pencil", label: "Quick edit") {
                        onQuickEdit()
                        onDismiss()
                    }
                    divider
                }

                row(icon: "square.and.pencil", label: "Add note") {
                    onAddNote()
                    onDismiss()
                }


                divider
                row(icon: "point.3.connected.trianglepath.dotted", label: "See related entries") {
                    onSeeRelated()
                    onDismiss()
                }

                divider
                row(icon: "info.circle", label: "More info") {
                    onMoreInfo()
                    onDismiss()
                }
            }
            .frame(width: 240)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 0.6)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 24, y: 10)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.35 : 0.30))
            .frame(height: 0.5)
            .padding(.leading, 46)
    }

    private func row(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(TimelineActionMenuRowButtonStyle())
    }
}

private struct TimelineActionMenuRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? FactTrailTheme.aiSoftBackground(for: colorScheme).opacity(0.6)
                    : Color.clear
            )
    }
}

private struct TimelineAttachmentPreviewSheet: View {
    let document: StoredDocument
    let onClose: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewBody
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.system(size: 18, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Text(document.fileName)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .lineLimit(1)
                        Text(DateFormatter.factTrailDateTime.string(from: document.importedAt))
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let url = document.localFileURL {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(FactTrailGlassButtonStyle())
                    }

                    Button(role: .destructive) {
                        isShowingDeleteConfirm = true
                    } label: {
                        Label("Delete attachment", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailGlassButtonStyle())
                }
                .padding(20)
            }
            .factTrailScreenBackground()
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: onClose)
                }
            }
            .alert("Delete this attachment?", isPresented: $isShowingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: onDelete)
            } message: {
                Text("This will remove the file from the timeline entry and from My Documents.")
            }
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if document.fileType == .image, let url = document.localFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        } else {
            VStack(spacing: 10) {
                Image(systemName: document.fileType.systemImage)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                Text(document.fileType.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
            )
        }
    }
}

private struct TimelinePDFShareButton: View {
    let incident: Incident
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?

    var body: some View {
        Group {
            if let pdfURL {
                ShareLink(
                    item: pdfURL,
                    subject: Text("Coparo Summary"),
                    message: Text("Coparo documentation summary")
                ) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else if let pdfErrorMessage {
                Text(pdfErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                HStack {
                    ProgressView()
                    Text("Preparing PDF...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            preparePDF()
        }
    }

    private func preparePDF() {
        do {
            pdfURL = try IncidentPDFExporter.makePDF(for: incident)
            pdfErrorMessage = nil
        } catch {
            pdfURL = nil
            pdfErrorMessage = "PDF could not be prepared on this device."
        }
    }
}

private struct TimelineFullPDFShareButton: View {
    let incidents: [Incident]
    @State private var pdfURL: URL?
    @State private var pdfErrorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            if let pdfURL {
                ShareLink(
                    item: pdfURL,
                    subject: Text("Coparo Timeline"),
                    message: Text("Coparo timeline export")
                ) {
                    Label("Export Full Timeline PDF", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if let pdfErrorMessage {
                Text(pdfErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else {
                HStack {
                    ProgressView()
                    Text("Preparing timeline PDF...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .task(id: exportSignature) {
            preparePDF()
        }
    }

    private var exportSignature: String {
        incidents.map {
            [
                $0.id.uuidString,
                "\($0.incidentDate.timeIntervalSince1970)",
                $0.category,
                "\($0.originalNotes.count)",
                "\($0.neutralSummary.count)",
                "\($0.guidedAnswers.count)",
                "\($0.patternTags.count)"
            ].joined(separator: "-")
        }.joined(separator: "|")
    }

    private func preparePDF() {
        do {
            pdfURL = try IncidentPDFExporter.makeTimelinePDF(for: incidents)
            pdfErrorMessage = nil
        } catch {
            pdfURL = nil
            pdfErrorMessage = "Timeline PDF could not be prepared on this device."
        }
    }
}
