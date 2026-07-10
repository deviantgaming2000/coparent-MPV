import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AccountManager.self) private var account
    @AppStorage("hasAcceptedFactTrailDisclaimer") private var hasAcceptedDisclaimer = false
    @AppStorage("factTrailAppearance") private var appearanceRawValue = FactTrailAppearance.light.rawValue
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
    @State private var timelineTagFilter: String?
    @State private var pickUpStates: [String: PickUpItemState] = PickUpStateStore.load()
    @State private var saveErrorMessage: String?
    @State private var shouldShowNamePrompt = false
    @State private var isShowingSettings = false
    @State private var shouldShowResetConfirmation = false
    @State private var backupExportFile: BackupExportFile?
    @State private var isShowingRestorePicker = false
    @State private var pendingRestoreBundle: BackupBundle?
    @State private var shouldShowRestoreConfirmation = false
    @State private var dataTransferMessage: DataTransferMessage?
    @State private var shouldShowCheckInSheet = false
    @State private var pendingCheckInFollowUp: CheckIn?
    @State private var pendingCheckInIncidentDraft: IncidentDraft?
    @State private var pendingCheckInIncidentID: UUID?
    @State private var isShowingLaunchScreen = true
    @State private var isShowingPickUp = false
    /// When the user opens a full entry from the Pick Up sheet, we stash the id and
    /// push the editor after the sheet finishes dismissing (avoids nav-under-sheet).
    @State private var pickUpPendingEditID: UUID?

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
                        onExchangeRecord: { path.append(.exchangeRecord) },
                        onDocumentSomething: { path.append(.entry) },
                        onOpenDocuments: { path.append(.documents) },
                        onCheckIn: { shouldShowCheckInSheet = true },
                        onViewTimeline: { path.append(.timeline) },
                        onViewInsights: { path.append(.insights) },
                        onEditName: { shouldShowNamePrompt = true },
                        onOpenMenu: { isShowingSettings = true },
                        onOpenIncident: { incident in
                            path.append(.edit(incident.id))
                        },
                        onOpenExchangeRecord: { _ in
                            path.append(.timeline)
                        },
                        onPickUp: { isShowingPickUp = true }
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
                        },
                        onFinish: { path.removeAll() }
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
                        },
                        onFinish: {
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
                        },
                        onFinish: {
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
                        allDocuments: storedDocuments,
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
                        onInsights: { path = [.insights] },
                        initialTagFilter: timelineTagFilter
                    )
                case .insights:
                    InsightsScreenView(
                        entries: timelineEntryInputs,
                        aiService: aiService,
                        onHome: { path = [] },
                        onTimeline: { timelineTagFilter = nil; path = [.timeline] },
                        onViewEntries: { tag in
                            timelineTagFilter = tag
                            path = [.timeline]
                        }
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
                            originalLocked: incident.isOriginalLocked,
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
                        },
                        onTimeline: { path = [.timeline] },
                        onInsights: { path = [.insights] },
                        linkedEntryTitle: { document in
                            linkedEntryTitle(for: document)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $isShowingPickUp, onDismiss: {
            if let id = pickUpPendingEditID {
                pickUpPendingEditID = nil
                path.append(.edit(id))
            }
        }) {
            PickUpView(
                incidents: incidents.filter { $0.exchangeRecordID == nil && $0.needsMoreDetail },
                onOpenIncident: { incident in
                    pickUpPendingEditID = incident.id
                    isShowingPickUp = false
                },
                onSaveIncident: { updateIncident($0) }
            )
            .presentationDragIndicator(.visible)
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
                    onClose: {
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
                    onDelete: {
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
            try? await Task.sleep(for: .seconds(1.9))
            withAnimation(.easeInOut(duration: 0.45)) {
                isShowingLaunchScreen = false
            }
            presentPendingCheckInFollowUpIfNeeded()
        }
        .sheet(isPresented: $shouldShowNamePrompt) {
            UserNameSetupView(userName: $userName)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $shouldShowCheckInSheet) {
            CheckInSheetView { checkIn in
                saveCheckIn(checkIn)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            .presentationDragIndicator(.visible)
        }
        .alert("Reset all data?", isPresented: $shouldShowResetConfirmation) {
            Button("Reset Everything", role: .destructive, action: resetAllData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every logged record, exchange, check-in, note, and document on this device, and returns the app to its first-launch state. This cannot be undone.")
        }
        .sheet(item: $backupExportFile) { file in
            ShareSheet(items: [file.url])
        }
        .fileImporter(
            isPresented: $isShowingRestorePicker,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            handleRestorePick(result)
        }
        .alert("Restore this backup?", isPresented: $shouldShowRestoreConfirmation, presenting: pendingRestoreBundle) { bundle in
            Button("Replace All Data", role: .destructive) {
                applyRestore(bundle)
                pendingRestoreBundle = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreBundle = nil
            }
        } message: { bundle in
            Text("This replaces everything currently in Coparo with the \(bundle.recordCount) record\(bundle.recordCount == 1 ? "" : "s") in this backup (from \(bundle.exportedAt.formatted(date: .abbreviated, time: .shortened))). This cannot be undone.")
        }
        .alert(item: $dataTransferMessage) { message in
            Alert(title: Text(message.title), message: Text(message.body), dismissButton: .default(Text("OK")))
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                onExport: {
                    isShowingSettings = false
                    runAfterSheetDismiss { exportBackup() }
                },
                onRestore: {
                    isShowingSettings = false
                    runAfterSheetDismiss { isShowingRestorePicker = true }
                },
                onReset: {
                    isShowingSettings = false
                    runAfterSheetDismiss { shouldShowResetConfirmation = true }
                }
            )
        }
    }

    /// Presents a follow-up sheet/alert only after the settings sheet has finished
    /// dismissing — presenting during the dismissal makes SwiftUI drop it.
    private func runAfterSheetDismiss(_ action: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.45))
            action()
        }
    }

    private var selectedAppearance: FactTrailAppearance {
        FactTrailAppearance(rawValue: appearanceRawValue) ?? .light
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

    /// Resolves the title of the first timeline entry a document is linked to, for the
    /// documents list's "Linked · <entry>" label. Returns nil when the document is standalone.
    private func linkedEntryTitle(for document: StoredDocument) -> String? {
        guard !document.linkedTimelineItemIds.isEmpty else { return nil }
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
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for linkedID in document.linkedTimelineItemIds {
            if let item = byID[linkedID] {
                return item.title
            }
        }
        return nil
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

    /// Thin entries the app suggests strengthening, minus any the user set aside or
    /// ignored — drives the Insights "Pick up where you left off" card.
    private var pickUpItems: [PickUpItem] {
        incidents
            .filter { $0.exchangeRecordID == nil && $0.needsMoreDetail }
            .filter { (pickUpStates[$0.id.uuidString] ?? .pending) == .pending }
            .prefix(5)
            .map { incident in
                PickUpItem(
                    id: incident.id.uuidString,
                    title: TimelineItem.incident(incident).title,
                    suggestion: incident.detailSuggestion
                )
            }
    }

    private func setPickUpState(_ state: PickUpItemState, for id: String) {
        pickUpStates[id] = state
        PickUpStateStore.save(pickUpStates)
    }

    private func openIncidentForDetail(id: String) {
        guard let uuid = UUID(uuidString: id),
              incidents.contains(where: { $0.id == uuid }) else { return }
        path.append(.edit(uuid))
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

    /// Wipes every persisted record and returns the app to its first-launch state.
    /// Deletes all on-disk stores (records, exchanges, check-ins, entries, documents
    /// and their imported files), clears UserDefaults-backed notes, empties in-memory
    /// state, and forgets the saved name so onboarding is shown again.
    private func resetAllData() {
        incidentStore.deleteAll()
        exchangeRecordStore.deleteAll()
        entryStore.deleteAll()
        checkInStore.deleteAll()
        documentStore.deleteAll()
        UserDefaults.standard.removeObject(forKey: linkedNotesStorageKey)
        UserDefaults.standard.removeObject(forKey: PeopleStore.key)
        CustodyScheduleStore.clear()

        incidents = []
        exchangeRecords = []
        entries = []
        checkIns = []
        linkedNotes = []
        storedDocuments = []
        saveErrorMessage = nil

        // Clear any in-flight flow state that referenced the records we just deleted,
        // so nothing (e.g. a pending check-in follow-up) can re-present stale data.
        pendingCheckInFollowUp = nil
        pendingCheckInIncidentDraft = nil
        pendingCheckInIncidentID = nil
        pendingExchangeDraft = nil
        pendingExchangeRecordID = nil
        activeReviewSummary = nil
        isShowingReview = false
        shouldShowCheckInSheet = false

        path = []
        userName = ""
        hasAcceptedDisclaimer = false

        // Account and first-run state so a reset returns to a true fresh install.
        AccountStore.clear()
        UserDefaults.standard.removeObject(forKey: "coparoHasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "coparoHideSignInPrompt")
        account.signOut()
    }

    // MARK: - Backup & restore

    /// Builds a single portable backup file and hands it to the share sheet.
    private func exportBackup() {
        do {
            let url = try BackupService.writeBackup(
                incidents: incidents,
                exchangeRecords: exchangeRecords,
                entries: entries,
                checkIns: checkIns,
                documents: storedDocuments,
                linkedNotes: linkedNotes,
                now: Date()
            )
            backupExportFile = BackupExportFile(url: url)
        } catch {
            dataTransferMessage = DataTransferMessage(
                title: "Backup failed",
                body: "Your records could not be exported on this device. \(error.localizedDescription)"
            )
        }
    }

    private func handleRestorePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                pendingRestoreBundle = try BackupService.readBackup(from: url)
                shouldShowRestoreConfirmation = true
            } catch {
                dataTransferMessage = DataTransferMessage(
                    title: "Couldn't open backup",
                    body: error.localizedDescription
                )
            }
        case .failure(let error):
            dataTransferMessage = DataTransferMessage(
                title: "Couldn't open backup",
                body: error.localizedDescription
            )
        }
    }

    /// Replaces all current data with a backup's contents, then reloads in-memory state.
    private func applyRestore(_ bundle: BackupBundle) {
        do {
            try incidentStore.saveIncidents(bundle.incidents)
            try exchangeRecordStore.saveExchangeRecords(bundle.exchangeRecords)
            try entryStore.saveEntries(bundle.entries)
            try checkInStore.saveCheckIns(bundle.checkIns)
            try documentStore.saveDocuments(bundle.documents)
            try BackupService.restoreDocumentFiles(bundle.files)

            let notesData = try JSONEncoder().encode(bundle.linkedNotes)
            UserDefaults.standard.set(notesData, forKey: linkedNotesStorageKey)

            incidents = incidentStore.loadIncidents()
            exchangeRecords = exchangeRecordStore.loadExchangeRecords()
            entries = entryStore.loadEntries()
            checkIns = checkInStore.loadCheckIns()
            linkedNotes = loadLinkedNotes()
            storedDocuments = documentStore.loadDocuments()
            saveErrorMessage = nil

            path = []
            dataTransferMessage = DataTransferMessage(
                title: "Backup restored",
                body: "Your records were restored from the backup."
            )
        } catch {
            dataTransferMessage = DataTransferMessage(
                title: "Restore failed",
                body: "The backup could not be fully restored. \(error.localizedDescription)"
            )
        }
    }
}

/// Wraps a generated backup file so `.sheet(item:)` can present the share sheet for it.
private struct BackupExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// A one-off success/error notice shown after a backup or restore.
private struct DataTransferMessage: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

/// Bridges UIActivityViewController (the system share sheet) into SwiftUI.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The launch screen. Light and on-theme by default (follows the app's
/// appearance): a soft cream field with two slowly drifting accent blooms, and
/// an animated logo - the gradient mark springs in, a soft halo breathes behind
/// it, and a single sheen sweeps across it once as the wordmark settles.
private struct FactTrailSplashView: View {
    var body: some View { CoparoSplashView() }
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
            // The entry's title should never be a raw category that reads like a
            // type ("Exchange", "Other"). Exchange isn't an entry category; if one
            // slipped through, title it descriptively and let the category map away.
            switch incident.category {
            case IncidentCategory.exchange.rawValue:
                return "Exchange details"
            case IncidentCategory.other.rawValue, "":
                return "Entry"
            default:
                return incident.category
            }
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

    /// Plain-English explanation of why this entry is flagged, shown when the user
    /// taps the amber "Flagged" badge.
    var flagReason: String? {
        guard isFlagged else { return nil }
        switch self {
        case .incident(let incident):
            let patterns = incident.patternTags
                .filter { $0 == .safetyConcern }
                .map(\.displayName)
            if !patterns.isEmpty {
                return "Flagged for a safety concern based on what you described."
            }
            return "Flagged for attention."
        case .exchangeRecord:
            return "Flagged because an incident is linked to this exchange."
        case .checkIn:
            return "Flagged because its follow-up hasn't been completed yet."
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Welcome to Coparo")
                        .font(.largeTitle.bold())
                    Text("A calm, private place to keep track of your co-parenting - the events, exchanges, and little details that are easy to forget.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    OnboardingHighlight(icon: "note.text", text: "Jot things down as they happen. Add a little or a lot - whatever you have time for.")
                    OnboardingHighlight(icon: "clock", text: "Everything is time-stamped and organized for you automatically.")
                    OnboardingHighlight(icon: "lock", text: "Your records stay private on your device.")
                }

                Text("Coparo helps you organize your own records. It doesn't provide legal advice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAccept) {
                    Text("Get started")
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

private struct OnboardingHighlight: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26)
            Text(text)
                .font(.callout)
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

                Text("What should we call you?")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            TextField("Your name", text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .factTrailGlassCard(cornerRadius: 18)

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
    let onExchangeRecord: () -> Void
    let onDocumentSomething: () -> Void
    let onOpenDocuments: () -> Void
    let onCheckIn: () -> Void
    let onViewTimeline: () -> Void
    var onViewInsights: () -> Void = {}
    let onEditName: () -> Void
    var onOpenMenu: () -> Void = {}
    let onOpenIncident: (Incident) -> Void
    let onOpenExchangeRecord: (ExchangeRecord) -> Void
    var onPickUp: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountManager.self) private var account
    @AppStorage("coparoHideSignInPrompt") private var hideSignInPrompt = false
    @State private var showingAccountFromBanner = false

    /// Standalone entries that are thin enough to invite strengthening. Drives the
    /// "Pick up where you left off" card's count and visibility.
    private var incidentsNeedingDetail: [Incident] {
        incidents
            .filter { $0.exchangeRecordID == nil && $0.needsMoreDetail }
            .sorted { $0.incidentDate > $1.incidentDate }
    }

    private var pickUpSubtitle: String {
        let count = incidentsNeedingDetail.count
        return count == 1
            ? "1 entry could use a little more detail."
            : "\(count) entries could use a little more detail."
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    header
                    signInBanner
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
                            title: "Record an event",
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

                        if !incidentsNeedingDetail.isEmpty {
                            HomeActionCard(
                                iconAssetName: "codoc-info-circle",
                                title: "Pick up where you left off",
                                subtitle: pickUpSubtitle,
                                badgeText: "\(incidentsNeedingDetail.count)",
                                style: .standard,
                                action: onPickUp
                            )
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)

            HomeBottomNavigation(activeTab: .home, onTimeline: onViewTimeline, onInsights: onViewInsights)
        }
        .background(HomePalette.background(for: colorScheme).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAccountFromBanner) {
            NavigationStack { AccountView() }
        }
    }

    @ViewBuilder
    private var signInBanner: some View {
        if !account.isSignedIn && !hideSignInPrompt {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 20))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up your account")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("Create a local account for your profile.")
                        .font(.system(size: 12))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                }
                Spacer(minLength: 8)
                Button {
                    showingAccountFromBanner = true
                } label: {
                    Text("Sign in")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(FactTrailTheme.primaryAction(for: colorScheme))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation { hideSignInPrompt = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(FactTrailTheme.aiSoftBackground(for: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var header: some View {
        HStack {
            Button {
                onOpenMenu()
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
            // Only a genuine safety concern flags an entry, matching the timeline's
            // flag logic so a flag always has a surfaced, explainable reason.
            return incident.patternTags.contains(.safetyConcern)
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

// MARK: - Pick up where you left off

/// A lightweight, one-question-at-a-time follow-up. Instead of reopening the whole
/// edit form, it asks for the single most useful missing detail and saves just that
/// field — which is timestamped and audited via `Incident.updated(from:)` and never
/// touches the locked original text.
private struct PickUpFollowUpSheet: View {
    let incident: Incident
    let onSave: (Incident) -> Void
    let onOpenFullEntry: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var value = ""

    private enum Field { case people, location }

    private var field: Field? {
        if incident.peopleInvolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .people }
        if incident.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .location }
        return nil
    }

    private var question: String {
        switch field {
        case .people: return "Who was involved?"
        case .location: return "Where did this happen?"
        case .none: return "Add a detail"
        }
    }

    private var placeholder: String {
        switch field {
        case .people: return "e.g. Me, Jordan, the kids"
        case .location: return "e.g. School pickup, home"
        case .none: return "Add a note"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(FactTrailTheme.aiAccent(for: colorScheme))
                        .frame(width: 6, height: 6)
                    Text("ONE QUICK THING")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .tracking(2)
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                }
                Text(question)
                    .font(.system(size: 25, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            }

            if field == .people {
                // Tap yourself, your co-parent, or kids from My people — with a
                // freehand fallback — instead of typing every name.
                PeopleTagField(text: $value)
            } else {
                TextField(placeholder, text: $value, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                    }
            }

            Button(action: save) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Open the full entry instead", action: onOpenFullEntry)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
    }

    private func save() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var draft = incident.draft
        switch field {
        case .people: draft.peopleInvolved = trimmed
        case .location: draft.location = trimmed
        case .none: break
        }
        onSave(incident.updated(from: draft))
    }
}

/// Lists the standalone entries that are still thin, so the user can open each one and
/// add the missing specifics. The list is passed in already filtered; when the user
/// strengthens an entry it drops out on the next appearance, and the home card's count
/// updates to match.
private struct PickUpView: View {
    let incidents: [Incident]
    let onOpenIncident: (Incident) -> Void
    var onSaveIncident: (Incident) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var followUpIncident: Incident?

    private let entryColor = Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x8C / 255)

    var body: some View {
        VStack(spacing: 0) {
            header

            if incidents.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A few entries could use a little more detail. Strengthening them takes a minute and makes your record more complete.")
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)

                        ForEach(incidents) { incident in
                            Button {
                                followUpIncident = incident
                            } label: {
                                card(incident)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .factTrailScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $followUpIncident) { incident in
            PickUpFollowUpSheet(
                incident: incident,
                onSave: { updated in
                    onSaveIncident(updated)
                    followUpIncident = nil
                },
                onOpenFullEntry: {
                    followUpIncident = nil
                    onOpenIncident(incident)
                }
            )
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
    }

    // Presented as a bottom sheet: swipe down (or the drag indicator) dismisses it,
    // so there's no top-left back button. The title just anchors the sheet.
    private var header: some View {
        Text("Pick up where you left off")
            .font(.system(size: 17, weight: .semibold, design: .default))
            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    private func card(_ incident: Incident) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(entryColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(categoryLabel(incident))
                        .font(.system(size: 9.5, weight: .semibold, design: .default))
                        .tracking(0.4)
                        .foregroundStyle(entryColor)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(entryColor.opacity(0.12)))
                    Text(incident.incidentDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }

                Text(displayTitle(incident))
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .lineLimit(2)

                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.top, 1)
                    Text(incident.detailSuggestion)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.4))
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 4, y: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            Text("You're all caught up.")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Every entry has the detail it needs.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryLabel(_ incident: Incident) -> String {
        let trimmed = incident.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty ? "Entry" : trimmed).uppercased()
    }

    private func displayTitle(_ incident: Incident) -> String {
        let notes = incident.originalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = notes.split(separator: "\n").first.map(String.init), !firstLine.isEmpty {
            return firstLine
        }
        let category = incident.category.trimmingCharacters(in: .whitespacesAndNewlines)
        return category.isEmpty ? "Untitled entry" : category
    }
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

struct HomeBottomNavigation: View {
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

enum BottomNavTab {
    case home, timeline, insights, documents
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
    @State private var isShowingFileImporter = false
    @State private var pendingUpload: PendingUpload?
    @State private var incidentLocationManager = ExchangeLocationManager()
    @State private var speechTranscriber = SpeechTranscriber()
    @State private var voiceBaseNotes = ""
    @State private var isShowingDateClarification = false
    @State private var userProvidedIncidentDate: Bool
    @State private var localReviewSummary: IncidentSummaryDraft?
    @State private var isShowingLocalReview = false
    @State private var isShowingDraftSaved = false

    let mode: EntryMode
    let aiService: any AIService
    /// When editing an entry whose 5-minute window has passed, the original text is
    /// immutable — only supplemental fields can be added.
    let originalLocked: Bool
    let onCreateSummary: (IncidentSummaryDraft) -> Void
    let onSaveCreatedIncident: ((Incident) -> Void)?
    let onSaveEdit: ((IncidentDraft) -> Void)?
    /// Dismisses the whole entry flow back to Home (e.g. "Delete entry" on the
    /// post-save review, which discards the draft without saving it).
    let onFinish: () -> Void

    init(
        initialDraft: IncidentDraft = IncidentDraft(),
        mode: EntryMode = .create,
        aiService: any AIService = MockAIService(),
        originalLocked: Bool = false,
        onCreateSummary: @escaping (IncidentSummaryDraft) -> Void,
        onSaveCreatedIncident: ((Incident) -> Void)? = nil,
        onSaveEdit: ((IncidentDraft) -> Void)? = nil,
        onFinish: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: initialDraft)
        _aiSuggestion = State(initialValue: initialDraft.aiAnalysis)
        _isShowingOptionalDetails = State(initialValue: mode == .edit)
        _userProvidedIncidentDate = State(initialValue: mode == .edit)
        self.mode = mode
        self.aiService = aiService
        self.originalLocked = originalLocked
        self.onCreateSummary = onCreateSummary
        self.onSaveCreatedIncident = onSaveCreatedIncident
        self.onSaveEdit = onSaveEdit
        self.onFinish = onFinish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                incidentTextCard
                if originalLocked {
                    lockBanner
                }
                dictationStatusRow
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
        .overlay(alignment: .bottom) {
            if isShowingDraftSaved {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Draft saved")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Text("Finish it anytime from Pick up where you left off.")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(FactTrailTheme.surface(for: colorScheme))
                        .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
                )
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(mode == .create ? "New entry" : "Edit entry")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
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
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .text, .rtf, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(item: $pendingUpload) { upload in
            AttachmentUploadSheet(
                upload: upload,
                onAttached: { attachment in
                    draft.evidenceAttachments.append(attachment)
                },
                onRemove: { attachment in
                    draft.evidenceAttachments.removeAll { $0.id == attachment.id }
                },
                onDone: {
                    pendingUpload = nil
                }
            )
            .presentationDetents([.height(290)])
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    if mode == .create {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Back")
                        }
                    } else {
                        Text("Cancel")
                    }
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
                }
            )
        }
        .navigationDestination(isPresented: $isShowingLocalReview) {
            if let localReviewSummary {
                SummaryReviewView(
                    summaryDraft: localReviewSummary,
                    isGeneratingSummary: isGeneratingFinalDocumentation,
                    generationError: finalDocumentationErrorMessage,
                    onGenerateSummary: { generateFinalDocumentationForReview() },
                    onClose: {
                        onSaveCreatedIncident?(localReviewSummary.incident)
                        self.localReviewSummary = nil
                        self.isShowingLocalReview = false
                    },
                    onDelete: {
                        self.localReviewSummary = nil
                        self.isShowingLocalReview = false
                        onFinish()
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

    private var lockBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            Text("The original description is locked. You can still add details below — each addition is timestamped.")
                .font(.system(size: 12.5, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FactTrailTheme.border(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.35))
        )
    }

    @ViewBuilder
    private var dictationStatusRow: some View {
        if speechTranscriber.isRecording {
            HStack(spacing: 7) {
                Circle()
                    .fill(.red)
                    .frame(width: 7, height: 7)
                Text("Listening…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                Spacer()
            }
            .padding(.horizontal, 2)
            .transition(.opacity)
        } else if let dictationError = speechTranscriber.errorMessage {
            Text(dictationError)
                .font(.system(size: 13))
                .foregroundStyle(.red)
                .padding(.horizontal, 2)
        }
    }

    private var incidentTextCard: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $draft.originalNotes)
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme).opacity(originalLocked ? 0.7 : 1))
                .lineSpacing(6)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, originalLocked ? 16 : 56)
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .disabled(originalLocked)
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

            // No dictation into a locked original — it can't be changed after 5 minutes.
            if !originalLocked {
                Button {
                    toggleDictation()
                } label: {
                    Group {
                        if speechTranscriber.isRecording {
                            Image(systemName: "stop.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(.red)
                        } else {
                            Image("codoc-microphone")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 17, height: 17)
                                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        }
                    }
                    .frame(width: 38, height: 38)
                    .background(
                        (speechTranscriber.isRecording ? Color.red : FactTrailTheme.aiAccent(for: colorScheme))
                            .opacity(0.12),
                        in: Circle()
                    )
                }
                .buttonStyle(HomePressButtonStyle())
                .accessibilityLabel(speechTranscriber.isRecording ? "Stop dictation" : "Start dictation")
                .padding(.trailing, 12)
                .padding(.bottom, 11)
            }
        }
        // The card clips its contents to the rounded border (matching the reference
        // `.input-card { overflow: hidden }`), so the left accent bar follows the
        // rounded corners instead of poking past them, and the mic stays contained.
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [
                            FactTrailTheme.aiAccent(for: colorScheme),
                            FactTrailTheme.primaryAction(for: colorScheme)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: 3)
                    .opacity(0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.06), radius: 8, y: 2)
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
                isShowingFileImporter = true
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
                    PeopleInvolvedRow(iconAssetName: "codoc-people", text: $draft.peopleInvolved)
                    SpecificsTextRow(iconAssetName: "codoc-location-pin", placeholder: "Location", text: $draft.location)

                    // Explicitly labeled so the app-assigned category reads as a field,
                    // not a stray value floating under the toggle.
                    HStack {
                        Text("Category")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Spacer()
                        Picker("Category", selection: Binding(
                            get: { draft.category },
                            set: { draft.category = $0; draft.categoryWasSuggested = false }
                        )) {
                            // Exchange isn't an entry category (it's a check-in kind), so
                            // it's excluded from the entry picker.
                            ForEach(IncidentCategory.allCases.filter { $0 != .exchange }) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(FactTrailTheme.aiAccent(for: colorScheme))
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
                    saveAndFinishLater()
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

    /// Persists the entry quietly as a draft (skipping the review step) and shows a
    /// brief confirmation, so "Save and finish this later" gives real feedback.
    private func saveAndFinishLater() {
        withAnimation(.snappy) { isShowingDraftSaved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            speechTranscriber.stopTranscribing()
            applyCapturedIncidentLocationIfNeeded()
            if draft.patternTags.isEmpty {
                draft.patternTags = NeutralSummaryGenerator.suggestedPatternTags(for: draft)
            }
            let summary = NeutralSummaryGenerator.makeSummary(from: draft)
            if let onSaveCreatedIncident {
                onSaveCreatedIncident(summary.incident)
            } else {
                onCreateSummary(summary)
            }
        }
    }

    private func saveEntry() {
        // Only ask "when did this happen?" when there's no date context already. If the
        // user opened the specifics section, the date field lives there (defaulting to
        // now), so the bottom-sheet prompt would be redundant.
        if mode == .create && !userProvidedIncidentDate && !isShowingOptionalDetails {
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

    /// Reads the picked document up front (while its security scope is valid) and hands the
    /// bytes to the upload sheet, which shows the reference-style confirmation.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let fileName = url.lastPathComponent
                attachmentErrorMessage = nil
                // Present the confirmation sheet on the next runloop tick: presenting it
                // synchronously here collides with the file importer's own dismissal and
                // SwiftUI silently drops the sheet.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.35))
                    pendingUpload = PendingUpload(kind: .file, fileName: fileName, data: data)
                }
            } catch {
                attachmentErrorMessage = "That file could not be read on this device."
            }
        case .failure(let error):
            attachmentErrorMessage = "Could not import file: \(error.localizedDescription)"
        }
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
                // Never overwrite a category the user explicitly picked; only fill the
                // neutral default, and mark it as suggested so the UI can label it.
                if draft.category == .other {
                    draft.category = suggestion.suggestedCategory
                    draft.categoryWasSuggested = true
                }
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

    /// Generates the documentation summary from the post-save review screen, then
    /// rebuilds `localReviewSummary` so the review re-renders with the summary card.
    /// The enriched draft is what gets persisted when the user taps Close.
    private func generateFinalDocumentationForReview() {
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
                localReviewSummary = NeutralSummaryGenerator.makeSummary(from: draft)
            } catch {
                finalDocumentationErrorMessage = error.localizedDescription
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

/// "People involved" as a labeled row wrapping the shared `PeopleTagField`.
private struct PeopleInvolvedRow: View {
    let iconAssetName: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SpecificsIcon(assetName: iconAssetName)
            VStack(alignment: .leading, spacing: 8) {
                Text("People involved")
                    .font(.system(size: 13.5, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                PeopleTagField(text: $text)
            }
        }
    }
}

/// Tag-style people picker: tap yourself and anyone from My people, with a freehand
/// "add someone else" fallback. Selection is stored back into the comma-separated
/// `text` binding so the underlying model and summaries are unchanged. Names already
/// on an entry that aren't in My people still appear as tags so edits never drop them.
private struct PeopleTagField: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("factTrailUserName") private var userName = ""
    @State private var savedPeople: [SavedPerson] = []
    @State private var addDraft = ""

    private var selectedNames: [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var selfName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Me" : trimmed
    }

    /// Yourself first, then everyone in My people, then any already-selected names
    /// that aren't in either list (freehand entries).
    private var allTags: [String] {
        var names: [String] = [selfName]
        for person in savedPeople where !names.contains(where: { $0.caseInsensitiveCompare(person.name) == .orderedSame }) {
            names.append(person.name)
        }
        for name in selectedNames where !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.append(name)
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlexibleWrap(spacing: 8) {
                ForEach(allTags, id: \.self) { name in
                    personChip(name)
                }
            }

            // Freehand fallback: add someone who isn't saved in My people.
            HStack(spacing: 8) {
                TextField("Add someone else", text: $addDraft)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .textInputAutocapitalization(.words)
                    .onSubmit(commitAdd)
                if !addDraft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: commitAdd) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 2)
        }
        .onAppear { savedPeople = PeopleStore.load() }
    }

    private func personChip(_ name: String) -> some View {
        let isSelected = selectedNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        return Button {
            toggle(name)
        } label: {
            Text(name)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(isSelected ? .white : FactTrailTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? FactTrailTheme.aiAccent(for: colorScheme) : FactTrailTheme.surface(for: colorScheme),
                    in: Capsule()
                )
                .overlay {
                    Capsule().stroke(isSelected ? Color.clear : FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ name: String) {
        var names = selectedNames
        if let index = names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.remove(at: index)
        } else {
            names.append(name)
        }
        text = names.joined(separator: ", ")
    }

    private func commitAdd() {
        let name = addDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        addDraft = ""
        guard !name.isEmpty,
              !selectedNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        text = (selectedNames + [name]).joined(separator: ", ")
    }
}

private struct IncidentDateClarificationSheet: View {
    @Binding var selectedDate: Date
    let onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPickingTime = false
    @State private var detent: PresentationDetent = IncidentDateClarificationSheet.collapsedDetent

    private static let collapsedDetent: PresentationDetent = .height(250)
    private static let expandedDetent: PresentationDetent = .height(500)

    /// Treat a time within a couple of minutes of now as "just now" so the
    /// default reads naturally until the user deliberately picks another time.
    private var isJustNow: Bool {
        abs(selectedDate.timeIntervalSinceNow) < 120
    }

    private var whenLabel: String {
        isJustNow ? "Just now" : DateFormatter.factTrailDateTime.string(from: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("When did this happen?")
                    .font(.system(size: 23, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                Text("Set to now by default. Tap the time to change it.")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            }

            Button {
                withAnimation(.snappy(duration: 0.28)) {
                    isPickingTime.toggle()
                    detent = isPickingTime ? Self.expandedDetent : Self.collapsedDetent
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(whenLabel)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Text(isPickingTime ? "Pick the date and time" : "Tap to adjust")
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .rotationEffect(.degrees(isPickingTime ? 180 : 0))
                }
                .padding(14)
                .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.5), lineWidth: 1.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPickingTime {
                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
            }

            Button {
                onConfirm()
            } label: {
                Text("Save entry")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(FactTrailTheme.surface(for: colorScheme).ignoresSafeArea())
        .presentationDetents([Self.collapsedDetent, Self.expandedDetent], selection: $detent)
        .presentationDragIndicator(.visible)
        .onAppear {
            // This sheet only appears when no date was chosen yet, so anchor the
            // default to the moment of saving — that's what "Just now" means.
            if isJustNow { selectedDate = Date() }
        }
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
                title: "Suggested category",
                value: analysis.suggestedCategory.rawValue
            )

            AIInsightRow(
                title: "Why this category",
                value: analysis.categoryReason
            )

            if !analysis.missingInformation.isEmpty {
                AIInsightRow(
                    title: "Missing information",
                    value: analysis.missingInformation.joined(separator: ", ")
                )
            }

            if !analysis.evidenceMentioned.isEmpty {
                AIInsightRow(
                    title: "Evidence mentioned",
                    value: analysis.evidenceMentioned.joined(separator: ", ")
                )
            }

            if !analysis.patternTags.isEmpty {
                AIInsightRow(
                    title: "Possible pattern tags",
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
            Text("Final documentation summary")
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
                Text("Documentation completeness")
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
    var isGeneratingSummary: Bool = false
    var generationError: String? = nil
    var onGenerateSummary: (() -> Void)? = nil
    let onClose: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your entry is ready")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                ReviewSection(title: "What you logged", text: summaryDraft.draft.originalNotes)

                // Surface a category whenever there is one, flagging it as "Suggested"
                // when the app inferred it from the notes rather than the user choosing.
                if summaryDraft.draft.category != .other {
                    ReviewSection(
                        title: "Category",
                        text: summaryDraft.draft.category.rawValue,
                        showsSuggestedBadge: summaryDraft.draft.categoryWasSuggested
                    )
                }

                if !summaryDraft.draft.evidenceAttachments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attachments")
                            .font(.headline)
                        EvidenceAttachmentGrid(
                            attachments: summaryDraft.draft.evidenceAttachments,
                            onRemove: nil
                        )
                    }
                }

                summarySection

                VStack(spacing: 18) {
                    Button(action: onClose) {
                        Text("Close")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FactTrailPrimaryButtonStyle())
                    .controlSize(.large)

                    // Deliberately understated and set apart from the primary action:
                    // deleting a saved entry should be possible but never an easy
                    // mis-tap next to "Close".
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete this entry")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
        .factTrailScreenBackground()
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private var summarySection: some View {
        if let finalDocumentation = summaryDraft.draft.finalDocumentation {
            FinalDocumentationCard(finalDocumentation: finalDocumentation)
        } else if let onGenerateSummary {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: onGenerateSummary) {
                    HStack(spacing: 8) {
                        if isGeneratingSummary {
                            ProgressView()
                                .tint(FactTrailTheme.aiAccent(for: colorScheme))
                        }
                        Text(isGeneratingSummary ? "Generating…" : "Generate documentation summary")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FactTrailGlassButtonStyle())
                .controlSize(.large)
                .disabled(isGeneratingSummary)

                if let generationError {
                    Text(generationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
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

// MARK: - Attachment upload sheet (reference "Add file / photo / screenshot")

/// The three attachment kinds the entry screen can add, each with the reference's tint and icon.
enum AttachmentKind {
    case photo, screenshot, file

    var sheetTitle: String {
        switch self {
        case .photo: return "Add photo"
        case .screenshot: return "Add screenshot"
        case .file: return "Add file"
        }
    }

    var noun: String {
        switch self {
        case .photo: return "photo"
        case .screenshot: return "screenshot"
        case .file: return "file"
        }
    }

    var color: Color {
        switch self {
        case .photo: return Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x8C / 255)
        case .screenshot: return Color(red: 0x4F / 255, green: 0x8F / 255, blue: 0x8B / 255)
        case .file: return Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "photo"
        case .screenshot: return "text.bubble"
        case .file: return "doc"
        }
    }
}

/// A document the user just picked, awaiting confirmation in the upload sheet.
struct PendingUpload: Identifiable {
    let id = UUID()
    let kind: AttachmentKind
    let fileName: String
    let data: Data
}

/// Reference-style upload sheet: a brief "Adding…" spinner, then a confirmed card
/// (tinted thumb + filename + "Added to this entry" + remove) and a Done button.
private struct AttachmentUploadSheet: View {
    let upload: PendingUpload
    let onAttached: (EvidenceAttachment) -> Void
    let onRemove: (EvidenceAttachment) -> Void
    let onDone: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var attachment: EvidenceAttachment?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(FactTrailTheme.border(for: colorScheme))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 18)

            Text(upload.kind.sheetTitle)
                .font(.system(size: 17, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .padding(.bottom, 16)

            if let attachment {
                confirmedRow(attachment)
                    .padding(.bottom, 12)
            } else {
                progressView
            }

            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationBackground(FactTrailTheme.surface(for: colorScheme))
        .task { await confirm() }
    }

    private var progressView: some View {
        VStack(spacing: 14) {
            UploadSpinner(color: FactTrailTheme.aiAccent(for: colorScheme))
            Text("Adding \(upload.kind.noun)…")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func confirmedRow(_ attachment: EvidenceAttachment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(upload.kind.color.opacity(0.14))
                Image(systemName: upload.kind.systemImage)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(upload.kind.color)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .font(.system(size: 13.5, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Added to this entry")
                        .font(.system(size: 11.5, weight: .medium, design: .default))
                }
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            }

            Spacer(minLength: 0)

            Button {
                onRemove(attachment)
                onDone()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(FactTrailTheme.border(for: colorScheme).opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.vertical, 6)
    }

    /// Shows the "Adding…" beat briefly (matching the reference), then reveals the confirmed
    /// attachment and hands it back to the entry so it's saved with the record.
    private func confirm() async {
        guard attachment == nil else { return }
        try? await Task.sleep(for: .seconds(0.75))
        let created = EvidenceAttachment(id: UUID(), fileName: upload.fileName, data: upload.data)
        onAttached(created)
        withAnimation(.easeInOut(duration: 0.2)) {
            attachment = created
        }
    }
}

private struct UploadSpinner: View {
    let color: Color
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .frame(width: 44, height: 44)
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                spinning = true
            }
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
                    VStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255))
                        Text(attachment.fileName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255).opacity(0.08))
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
    var showsSuggestedBadge: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                if showsSuggestedBadge {
                    SuggestedBadge()
                }
            }
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A subtle marker that a value was auto-suggested by the app rather than entered by
/// the user — so a suggested category is never mistaken for the user's own choice.
private struct SuggestedBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text("Suggested")
            .font(.system(size: 10, weight: .semibold, design: .default))
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12), in: Capsule())
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
    /// All stored documents; standalone ones (not attached to any entry) appear as
    /// their own markers on the timeline.
    var allDocuments: [StoredDocument] = []
    let saveErrorMessage: String?
    let onEdit: (Incident) -> Void
    let onAddLinkedNote: (TimelineItem, String) -> Void
    let onDeleteAttachment: (StoredDocument) -> Void
    var onInsights: () -> Void = {}
    /// When opened from an Insight's "View entries in timeline", this scopes the
    /// timeline to that pattern's entries. Nil = show everything.
    var initialTagFilter: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var insightTagFilter: String?
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
                        if let insightTagFilter {
                            insightFilterBanner(tag: insightTagFilter)
                        }
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
                                    documents: standaloneDocuments,
                                    density: density,
                                    expandedItemIDs: $expandedItemIDs,
                                    notesFor: notes(for:),
                                    attachmentsFor: attachments(for:),
                                    onEdit: onEdit,
                                    onAddNote: beginAddNote,
                                    onSeeRelated: showRelatedEntries,
                                    onMoreInfo: { itemForMoreInfo = $0 },
                                    onAttachmentTapped: { previewAttachment = $0 },
                                    onDocumentTapped: { previewAttachment = $0 },
                                    onLongPress: presentActionMenu
                                )
                            case .list:
                                ListTimelineView(
                                    groupedItems: groupedItems,
                                    documents: standaloneDocuments,
                                    density: density,
                                    expandedItemIDs: $expandedItemIDs,
                                    notesFor: notes(for:),
                                    attachmentsFor: attachments(for:),
                                    onEdit: onEdit,
                                    onAddNote: beginAddNote,
                                    onSeeRelated: showRelatedEntries,
                                    onMoreInfo: { itemForMoreInfo = $0 },
                                    onAttachmentTapped: { previewAttachment = $0 },
                                    onDocumentTapped: { previewAttachment = $0 },
                                    onLongPress: presentActionMenu
                                )
                            case .calendar:
                                CalendarTimelineView(
                                    items: filteredTimelineItems,
                                    annotations: timelineAnnotations,
                                    documents: standaloneDocuments,
                                    mode: calendarMode,
                                    selectedDate: $selectedDate,
                                    onDocumentTapped: { previewAttachment = $0 }
                                )
                            }
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
        .disablesInteractivePop()
        .navigationTitle(selectedStyle == .calendar ? "Calendar" : "Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            // Seed the insight filter once when arriving from "View entries in timeline".
            if insightTagFilter == nil, let initialTagFilter {
                insightTagFilter = initialTagFilter
                selectedStyle = .list
            }
        }
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

    /// Documents not attached to any entry, shown as their own timeline markers.
    /// Hidden while a related/pattern filter is scoping the timeline to specific entries.
    private var standaloneDocuments: [StoredDocument] {
        guard relatedFilterSource == nil, insightTagFilter == nil, initialTagFilter == nil else { return [] }
        return allDocuments.filter { $0.linkedTimelineItemIds.isEmpty }
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
        // Newest first so a just-added entry appears at the top of the branch, matching
        // the list view. (Previously ascending, which buried new entries at the bottom.)
        filteredTimelineItems.sorted { $0.date > $1.date }
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
        var baseItems = timelineItems

        // Insight filter: scope to the entries behind a pattern the user tapped
        // "View entries in timeline" on.
        if let insightTagFilter {
            baseItems = baseItems.filter { matchesInsightTag($0, tag: insightTagFilter) }
        }

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

    /// Matches a timeline item to an Insight's tag. The recurring-pattern insights
    /// tag by an entry-tag display name; the flagged/consistency insights are special.
    private func matchesInsightTag(_ item: TimelineItem, tag: String) -> Bool {
        switch tag {
        case "flagged":
            return item.isFlagged
        case "checkin_consistency":
            if case .checkIn = item { return true }
            return false
        default:
            return item.tags.map(\.displayName).contains(tag)
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

    private func insightFilterBanner(tag: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            Text("Showing entries for \(insightTagLabel(tag))")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            Spacer(minLength: 6)
            Button("Clear") {
                withAnimation(.snappy) { insightTagFilter = nil }
            }
            .font(.system(size: 13, weight: .semibold, design: .default))
            .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.09))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.22), lineWidth: 1)
                }
        )
    }

    private func insightTagLabel(_ tag: String) -> String {
        switch tag {
        case "flagged": return "flagged entries"
        case "checkin_consistency": return "check-ins"
        default: return "\"\(tag)\""
        }
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
        // Kinds that appear as nodes on the timeline/calendar. Standalone documents
        // (added without being attached to an entry) get their own violet marker.
        HStack(spacing: 14) {
            legendItem("Entry", color: FactTrailTheme.primaryAction(for: colorScheme))
            legendItem("Check-in", color: FactTrailTheme.aiAccent(for: colorScheme))
            legendItem("Document", color: timelineDocumentColor)
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
    /// Standalone documents (not attached to an entry), interleaved as their own nodes.
    var documents: [StoredDocument] = []
    let density: TimelineDensity
    @Binding var expandedItemIDs: Set<String>
    let notesFor: (TimelineItem) -> [LinkedNote]
    let attachmentsFor: (TimelineItem) -> [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    var onDocumentTapped: (StoredDocument) -> Void = { _ in }
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
                case .document(let document):
                    TimelineDocumentRow(
                        document: document,
                        cardColumnWidth: cardColumnWidth,
                        gutterWidth: gutterWidth,
                        onTap: { onDocumentTapped(document) }
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
        // Items are newest-first; interleave annotations in the same order.
        var pendingAnnotations = annotations.sorted { $0.anchorDate > $1.anchorDate }
        var pendingDocuments = documents.sorted { $0.createdAt > $1.createdAt }

        for item in items {
            // Flush AI pattern annotations newer than this entry (so they sit above it).
            while let next = pendingAnnotations.first, next.anchorDate > item.date {
                rows.append(.annotation(next))
                pendingAnnotations.removeFirst()
            }
            // Flush standalone documents newer than this entry so they sit in date order.
            while let next = pendingDocuments.first, next.createdAt > item.date {
                appendYearMonthIfNeeded(for: next.createdAt, rows: &rows, currentYear: &currentYear, currentMonth: &currentMonth)
                rows.append(.document(next))
                pendingDocuments.removeFirst()
            }

            appendYearMonthIfNeeded(for: item.date, rows: &rows, currentYear: &currentYear, currentMonth: &currentMonth)
            rows.append(.item(item, itemIndex))
            itemIndex += 1
        }

        for annotation in pendingAnnotations {
            rows.append(.annotation(annotation))
        }
        for document in pendingDocuments {
            appendYearMonthIfNeeded(for: document.createdAt, rows: &rows, currentYear: &currentYear, currentMonth: &currentMonth)
            rows.append(.document(document))
        }
        return rows
    }

    /// Emits the year/month header rows when a row crosses into a new year or month.
    private func appendYearMonthIfNeeded(for date: Date, rows: inout [BranchRow], currentYear: inout Int?, currentMonth: inout Int?) {
        let year = Calendar.current.component(.year, from: date)
        let month = Calendar.current.component(.month, from: date)
        if currentYear != year {
            rows.append(.year(year))
            currentYear = year
            currentMonth = nil
        }
        if currentMonth != month {
            rows.append(.month(TimelineGroupKey(date: date).monthLabel))
            currentMonth = month
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

private enum BranchRow {
    case year(Int)
    case month(String)
    case item(TimelineItem, Int)
    case annotation(TimelineAnnotation)
    case document(StoredDocument)
}

/// Distinct violet used for standalone-document nodes across the timeline views, so a
/// document reads as its own kind of record rather than an entry or a check-in.
private let timelineDocumentColor = Color(hex: 0x7B6FAB)

/// A standalone document (not attached to an entry) shown as its own node on the
/// branch spine, tappable to preview.
private struct TimelineDocumentRow: View {
    let document: StoredDocument
    let cardColumnWidth: CGFloat
    let gutterWidth: CGFloat
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Color.clear
                .frame(width: cardColumnWidth, height: 1)

            Circle()
                .fill(timelineDocumentColor.opacity(0.15))
                .overlay { Circle().strokeBorder(timelineDocumentColor, lineWidth: 1.5) }
                .overlay {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(timelineDocumentColor)
                }
                .frame(width: gutterWidth * 0.55, height: gutterWidth * 0.55)
                .frame(width: gutterWidth)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                    Text("Document · \(DateFormatter.factTrailCompactDateTime.string(from: document.createdAt))")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(width: cardColumnWidth, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(timelineDocumentColor.opacity(colorScheme == .dark ? 0.16 : 0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(timelineDocumentColor.opacity(0.4), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
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
    var documents: [StoredDocument] = []
    let density: TimelineDensity
    @Binding var expandedItemIDs: Set<String>
    let notesFor: (TimelineItem) -> [LinkedNote]
    let attachmentsFor: (TimelineItem) -> [StoredDocument]
    let onEdit: (Incident) -> Void
    let onAddNote: (TimelineItem) -> Void
    let onSeeRelated: (TimelineItem) -> Void
    let onMoreInfo: (TimelineItem) -> Void
    let onAttachmentTapped: (StoredDocument) -> Void
    var onDocumentTapped: (StoredDocument) -> Void = { _ in }
    let onLongPress: (TimelineItem) -> Void

    private enum ListRow: Identifiable {
        case item(TimelineItem)
        case document(StoredDocument)

        var id: String {
            switch self {
            case .item(let item): return "item-\(item.id)"
            case .document(let document): return "document-\(document.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .item(let item): return item.date
            case .document(let document): return document.createdAt
            }
        }
    }

    /// The month keys across both entries and standalone documents, newest first.
    private var groupKeys: [TimelineGroupKey] {
        var keys = groupedItems.map(\.key)
        for document in documents {
            let key = TimelineGroupKey(date: document.createdAt)
            if !keys.contains(key) { keys.append(key) }
        }
        return keys.sorted { $0.sortDate > $1.sortDate }
    }

    private func rows(for key: TimelineGroupKey) -> [ListRow] {
        let items = (groupedItems.first { $0.key == key }?.items ?? []).map(ListRow.item)
        let docs = documents
            .filter { TimelineGroupKey(date: $0.createdAt) == key }
            .map(ListRow.document)
        return (items + docs).sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(groupKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 10) {
                    TimelineYearPill(year: key.year)
                    TimelineMonthLabel(month: key.monthLabel)
                    ForEach(rows(for: key)) { row in
                        switch row {
                        case .item(let item):
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
                        case .document(let document):
                            TimelineDocumentListRow(document: document, onTap: { onDocumentTapped(document) })
                        }
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

/// A standalone document as a compact card in the list view, tappable to preview.
private struct TimelineDocumentListRow: View {
    let document: StoredDocument
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(timelineDocumentColor)
                    .frame(width: 30, height: 30)
                    .background(timelineDocumentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("DOCUMENT")
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .tracking(0.6)
                        .foregroundStyle(timelineDocumentColor)
                    Text(document.title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(DateFormatter.factTrailCompactDateTime.string(from: document.createdAt))
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(FactTrailTheme.surface(for: colorScheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(timelineDocumentColor.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
    @State private var showingFlagReason = false

    var body: some View {
        let combinedAttachments = item.attachmentCount + attachmentCount
        // FlowLayout (not a fixed HStack) so the badges wrap to a new row instead of
        // forcing the card wider than its column — which, in the narrow branch view,
        // pushed cards off the left/right screen edges.
        FlowLayout(spacing: 7, rowSpacing: 7) {
            if !item.locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                badge("Location", systemImage: "mappin.and.ellipse")
            }
            if combinedAttachments > 0 {
                badge("\(combinedAttachments)", systemImage: "paperclip")
            }
            if item.isFlagged {
                // Amber is the app's flag/pattern color. Tapping explains why it's flagged.
                Button {
                    showingFlagReason = true
                } label: {
                    badge("Flagged", systemImage: "flag", tint: Color(hex: 0xD97706))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingFlagReason) {
                    Text(item.flagReason ?? "Flagged for attention.")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 260)
                        .padding(16)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    private func badge(_ text: String, systemImage: String, tint: Color? = nil) -> some View {
        let color = tint ?? FactTrailTheme.aiAccent(for: colorScheme)
        return Label(text, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
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

            // A check-in is a deliberate action, not an event that "occurred".
            TimelineDetailRow(
                label: { if case .checkIn = item { return "Checked in" } else { return "Occurred" } }(),
                value: DateFormatter.factTrailDateTime.string(from: item.date)
            )

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
            // The flag is shown once, as the amber badge on the card itself.
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
    @State private var speechTranscriber = SpeechTranscriber()
    @State private var voiceBaseNote = ""

    private var micColor: Color {
        speechTranscriber.isRecording ? .red : FactTrailTheme.aiAccent(for: colorScheme)
    }

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

            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $noteText)
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    .frame(minHeight: 140)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 46)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FactTrailTheme.surface(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    if speechTranscriber.isRecording {
                        Text("Listening…")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(.red)
                    }

                    Button {
                        toggleDictation()
                    } label: {
                        Image("codoc-microphone")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                            .foregroundStyle(micColor)
                            .frame(width: 38, height: 38)
                            .background(micColor.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(HomePressButtonStyle())
                    .accessibilityLabel(speechTranscriber.isRecording ? "Stop dictation" : "Start dictation")
                }
                .padding(.trailing, 10)
                .padding(.bottom, 8)
            }

            if let dictationError = speechTranscriber.errorMessage {
                Text(dictationError)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .onChange(of: speechTranscriber.transcript) { _, newTranscript in
            noteText = mergedNotes(base: voiceBaseNote, transcript: newTranscript)
        }
        .onDisappear {
            speechTranscriber.stopTranscribing()
        }
    }

    private func toggleDictation() {
        if speechTranscriber.isRecording {
            speechTranscriber.stopTranscribing()
        } else {
            voiceBaseNote = noteText
            Task {
                await speechTranscriber.startTranscribing()
            }
        }
    }

    /// Appends dictated speech after whatever the user has already typed, matching the
    /// entry screen's behavior.
    private func mergedNotes(base: String, transcript: String) -> String {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { return base }

        let cleanedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedBase.isEmpty else { return cleanedTranscript }

        return "\(cleanedBase)\n\n\(cleanedTranscript)"
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
    var annotations: [TimelineAnnotation] = []
    var documents: [StoredDocument] = []
    let mode: TimelineCalendarMode
    @Binding var selectedDate: Date
    var onDocumentTapped: (StoredDocument) -> Void = { _ in }
    @Environment(\.colorScheme) private var colorScheme
    @State private var visibleMonth = Date()
    @State private var custodySchedule: CustodySchedule? = CustodyScheduleStore.load()
    @State private var expandedDayItemIDs: Set<String> = []
    @State private var calendarNotes: [CalendarNote] = CalendarNoteStore.load()
    @State private var noteSheetContext: CalendarNoteSheetContext?
    /// One-time teaching flag: the "mark vacations and plans" hint shows until the
    /// user has created their first calendar note, then never again.
    @AppStorage("coparoHasMarkedPlans") private var hasMarkedPlans = false

    private let patternAmber = Color(hex: 0xD97706)

    /// Identifies which note (or a fresh one) the note sheet is editing.
    private struct CalendarNoteSheetContext: Identifiable {
        let id = UUID()
        var note: CalendarNote?
        var defaultDate: Date
    }

    /// AI pattern annotations anchored to a given calendar day.
    private func annotations(on date: Date) -> [TimelineAnnotation] {
        annotations.filter { Calendar.current.isDate($0.anchorDate, inSameDayAs: date) }
    }

    /// Standalone documents dated on a given calendar day.
    private func documents(on date: Date) -> [StoredDocument] {
        documents.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: date) }
    }

    /// Calendar notes whose range covers a given day.
    private func calendarNotes(covering date: Date) -> [CalendarNote] {
        calendarNotes.filter { $0.covers(date) }
    }

    private func saveCalendarNote(_ note: CalendarNote) {
        if let index = calendarNotes.firstIndex(where: { $0.id == note.id }) {
            calendarNotes[index] = note
        } else {
            calendarNotes.append(note)
        }
        CalendarNoteStore.save(calendarNotes)
        // First note saved: the teaching hint has done its job.
        hasMarkedPlans = true
        // Jump the calendar to the saved range so the result is always visible —
        // otherwise a note placed in another month looks like it silently vanished.
        selectedDate = note.startDate
        visibleMonth = note.startDate
    }

    private func deleteCalendarNote(_ note: CalendarNote) {
        calendarNotes.removeAll { $0.id == note.id }
        CalendarNoteStore.save(calendarNotes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthHeader

            legendRow

            if mode == .month {
                monthGrid
            } else {
                weekGrid
            }

            selectedDayCard

            if !hasMarkedPlans {
                plansHintCard
            }

            // When there's no schedule yet, the setup nudge sits at the bottom,
            // out of the way of the calendar itself.
            if custodySchedule == nil {
                custodySetupPrompt
            }
        }
        .onAppear {
            visibleMonth = selectedDate
            custodySchedule = CustodyScheduleStore.load()
            calendarNotes = CalendarNoteStore.load()
        }
        .sheet(item: $noteSheetContext) { context in
            CalendarNoteSheet(
                existing: context.note,
                defaultDate: context.defaultDate,
                onSave: saveCalendarNote,
                onDelete: deleteCalendarNote
            )
        }
    }

    @ViewBuilder
    private var legendRow: some View {
        if let schedule = custodySchedule {
            let shown = schedule.caregivers.filter { caregiver in
                schedule.cycle.contains(caregiver.id) || schedule.overrides.values.contains(caregiver.id)
            }
            // Just the whose-day color key — the day-to-day color change already reads
            // as the exchange, so a separate "Exchange" swatch was redundant.
            VStack(alignment: .leading, spacing: 6) {
                FlexibleWrap(spacing: 12) {
                    ForEach(shown) { caregiver in
                        calendarLegend(
                            caregiver.id == CustodyCaregiver.youID ? "Your days" : caregiver.name,
                            color: CustodyPalette.color(caregiver.colorIndex).opacity(0.28)
                        )
                    }
                    // The ring drawn around a day number when the kids change hands.
                    HStack(spacing: 5) {
                        Circle()
                            .stroke(FactTrailTheme.aiAccent(for: colorScheme), lineWidth: 2)
                            .frame(width: 11, height: 11)
                        Text("Exchange")
                            .lineLimit(1)
                    }
                    if !calendarNotes.isEmpty {
                        calendarLegend("Plans", color: calendarNoteColor.opacity(0.28))
                    }
                }
                .font(.system(size: 12, weight: .medium, design: .default))

                Text("A day is colored for whoever has the kids for most of it. Mid-day exchanges are counted to the parent with the larger share.")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        } else if !calendarNotes.isEmpty {
            // No custody schedule, but plans exist: still explain the rose highlight.
            FlexibleWrap(spacing: 12) {
                calendarLegend("Plans", color: calendarNoteColor.opacity(0.28))
            }
            .font(.system(size: 12, weight: .medium, design: .default))
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
        }
    }

    /// One-time nudge that teaches the Plans feature; tapping it starts a note on the
    /// selected day. Disappears for good once the first note is saved.
    private var plansHintCard: some View {
        Button {
            noteSheetContext = CalendarNoteSheetContext(note: nil, defaultDate: selectedDate)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(calendarNoteColor)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mark vacations and plans")
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text("Going away with the kids? Tap + Plans on any day to label a stretch of dates. It shows across the calendar without changing your schedule.")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(calendarNoteColor.opacity(0.07)))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(calendarNoteColor.opacity(0.25), lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private var custodySetupPrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Color-code whose day is whose")
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Set up your custody schedule from the menu and each day will be shaded for whoever has the kids.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
        .padding(.top, 4)
    }

    private var monthHeader: some View {
        HStack {
            Button {
                shiftPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(FactTrailGlassCardButtonStyle())

            Spacer()

            Text(headerTitle)
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Spacer()

            Button {
                shiftPeriod(by: 1)
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
                        isExchangeDay: isExchangeDay(date) || isCustodyExchange(date),
                        custodyColor: custodyColor(on: date),
                        hasPatternAnnotation: !annotations(on: date).isEmpty,
                        hasDocument: !documents(on: date).isEmpty,
                        hasCalendarNote: !calendarNotes(covering: date).isEmpty
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
                            ForEach(annotations(on: date)) { annotation in
                                HStack(spacing: 6) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(patternAmber)
                                    Text(annotation.text)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(patternAmber)
                                        .lineLimit(1)
                                }
                            }
                            ForEach(documents(on: date)) { document in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(timelineDocumentColor)
                                    Text(document.title)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(timelineDocumentColor)
                                        .lineLimit(1)
                                }
                            }
                            ForEach(calendarNotes(covering: date)) { note in
                                HStack(spacing: 6) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(calendarNoteColor)
                                    Text(note.title)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(calendarNoteColor)
                                        .lineLimit(1)
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    Text(selectedDaySubtitle)
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                Spacer()
                // Add a range note ("Taking the kids on vacation") starting on this day.
                Button {
                    noteSheetContext = CalendarNoteSheetContext(note: nil, defaultDate: selectedDate)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Plans")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 11)
                    .background(Capsule().fill(calendarNoteColor))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            ForEach(calendarNotes(covering: selectedDate)) { note in
                Button {
                    noteSheetContext = CalendarNoteSheetContext(note: note, defaultDate: selectedDate)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(calendarNoteColor)
                        Text(note.title)
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(note.rangeText)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(calendarNoteColor.opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            if let schedule = custodySchedule {
                custodyControlRow(schedule: schedule)
            }

            ForEach(annotations(on: selectedDate)) { annotation in
                HStack(spacing: 8) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(patternAmber)
                    Text(annotation.text)
                        .font(.system(size: 13, weight: .medium, design: .default))
                        .foregroundStyle(patternAmber)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider()

            let dayItems = items(on: selectedDate)
            let dayDocuments = documents(on: selectedDate)
            if dayItems.isEmpty && dayDocuments.isEmpty {
                Text("No records logged on this day.")
                    .font(.footnote)
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    .padding(14)
            } else {
                ForEach(dayDocuments) { document in
                    Button {
                        onDocumentTapped(document)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(timelineDocumentColor)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.title)
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                                Text("Document · \(DateFormatter.factTrailCompactDateTime.string(from: document.createdAt))")
                                    .font(.caption)
                                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
                ForEach(dayItems) { item in
                    let isExpanded = expandedDayItemIDs.contains(item.id)
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            if isExpanded {
                                expandedDayItemIDs.remove(item.id)
                            } else {
                                expandedDayItemIDs.insert(item.id)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
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
                                Image(systemName: "chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.5))
                                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            }

                            if isExpanded {
                                let summary = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                                Text(summary.isEmpty ? "No additional details recorded." : summary)
                                    .font(.system(size: 14, weight: .regular, design: .default))
                                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 10)
                                    .padding(.leading, 22)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .factTrailGlassCard(cornerRadius: 16)
    }

    private var selectedDaySubtitle: String {
        var parts: [String] = []
        if let caregiver = custodyCaregiver(on: selectedDate) {
            parts.append(caregiver.id == CustodyCaregiver.youID ? "Your day" : "\(caregiver.name)'s day")
        } else {
            parts.append("Parenting day")
        }
        if isExchangeDay(selectedDate) || isCustodyExchange(selectedDate) {
            parts.append("Exchange day")
        }
        return parts.joined(separator: " · ")
    }

    private func custodyControlRow(schedule: CustodySchedule) -> some View {
        let currentID = schedule.caregiverID(on: selectedDate)
        let isOverridden = schedule.overrides[CustodySchedule.dateKey(for: selectedDate)] != nil
        return HStack(spacing: 10) {
            if let caregiver = custodyCaregiver(on: selectedDate) {
                Circle()
                    .fill(CustodyPalette.color(caregiver.colorIndex))
                    .frame(width: 12, height: 12)
                Text(caregiver.id == CustodyCaregiver.youID ? "You have the kids" : "\(caregiver.name) has the kids")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            }
            Spacer()
            Menu {
                ForEach(schedule.caregivers) { caregiver in
                    let name = caregiver.id == CustodyCaregiver.youID ? "\(caregiver.name) (you)" : caregiver.name
                    Button {
                        setCustodyOverride(caregiver.id, for: selectedDate)
                    } label: {
                        if currentID == caregiver.id {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
                if isOverridden {
                    Divider()
                    Button("Follow schedule") {
                        setCustodyOverride(nil, for: selectedDate)
                    }
                }
            } label: {
                Text(isOverridden ? "Overridden" : "Change")
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.12)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.month(.wide).year())
    }

    /// The header reads the visible month in month mode, and the selected week's
    /// date range in week mode, so it always describes what the arrows will move.
    private var headerTitle: String {
        guard mode == .week else { return monthTitle }
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfMonth, for: selectedDate) else { return monthTitle }
        let start = week.start
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.day())), \(end.formatted(.dateTime.year()))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) - \(end.formatted(.dateTime.month(.abbreviated).day()))"
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

    /// In week mode the arrows step by one week (moving the selected week, which
    /// drives the week grid); in month mode they step by one month.
    private func shiftPeriod(by value: Int) {
        let calendar = Calendar.current
        if mode == .week {
            selectedDate = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) ?? selectedDate
            visibleMonth = selectedDate
        } else {
            visibleMonth = calendar.date(byAdding: .month, value: value, to: visibleMonth) ?? visibleMonth
            selectedDate = visibleMonth
        }
    }

    private func isExchangeDay(_ date: Date) -> Bool {
        items(on: date).contains {
            if case .exchangeRecord = $0 {
                return true
            }
            return false
        }
    }

    private func custodyCaregiver(on date: Date) -> CustodyCaregiver? {
        custodySchedule?.caregiver(on: date)
    }

    private func custodyColor(on date: Date) -> Color? {
        guard let caregiver = custodyCaregiver(on: date) else { return nil }
        return CustodyPalette.color(caregiver.colorIndex)
    }

    private func isCustodyExchange(_ date: Date) -> Bool {
        custodySchedule?.isExchange(on: date) ?? false
    }

    private func setCustodyOverride(_ caregiverID: String?, for date: Date) {
        guard var schedule = custodySchedule else { return }
        let key = CustodySchedule.dateKey(for: date)
        if let caregiverID {
            schedule.overrides[key] = caregiverID
        } else {
            schedule.overrides.removeValue(forKey: key)
        }
        custodySchedule = schedule
        CustodyScheduleStore.save(schedule)
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
    var custodyColor: Color? = nil
    var hasPatternAnnotation: Bool = false
    var hasDocument: Bool = false
    var hasCalendarNote: Bool = false
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let patternAmber = Color(hex: 0xD97706)

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
                    .overlay(alignment: .topTrailing) {
                        // Amber pattern blip: an AI-detected pattern begins or was last
                        // noted on this day.
                        if hasPatternAnnotation {
                            Circle()
                                .fill(patternAmber)
                                .frame(width: 6, height: 6)
                                .offset(x: 1, y: -1)
                        }
                    }

                HStack(spacing: 2) {
                    ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(item.timelineColor(for: colorScheme))
                            .frame(width: 5, height: 5)
                    }
                    if hasDocument {
                        Circle()
                            .fill(timelineDocumentColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(dayBackground)
                    // A calendar note (vacation, visit) covers this day: wash the whole
                    // cell in rose so the range reads as a block, over the custody tint.
                    if hasCalendarNote && isInVisibleMonth {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(calendarNoteColor.opacity(0.18))
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var isInVisibleMonth: Bool {
        Calendar.current.isDate(date, equalTo: visibleMonth, toGranularity: .month)
    }

    private var dayTextColor: Color {
        isInVisibleMonth
        ? FactTrailTheme.primaryText(for: colorScheme)
        : FactTrailTheme.mutedText(for: colorScheme).opacity(0.42)
    }

    private var dayBackground: Color {
        guard Calendar.current.isDate(date, equalTo: visibleMonth, toGranularity: .month) else {
            return .clear
        }
        if let custodyColor {
            return custodyColor.opacity(colorScheme == .dark ? 0.38 : 0.24)
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
            // Exchanges are a kind of check-in, so they share the accent teal node
            // rather than reading as a separate blue/periwinkle category.
            return FactTrailTheme.aiAccent(for: colorScheme)
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
        case .entry: return Color(hex: 0x2F5D8C)      // primary blue
        case .checkin: return Color(hex: 0x4F8F8B)    // accent teal
        case .exchange: return Color(hex: 0x4F8F8B)   // exchange is a check-in kind → teal
        case .document: return Color(hex: 0x6E7E99)   // palette slate (was off-palette emerald)
        case .flag: return Color(hex: 0xD97706)       // amber (established alert color)
        }
    }
}

private struct InsightsScreenView: View {
    let entries: [TimelineEntryInput]
    let aiService: any AIService
    let onHome: () -> Void
    let onTimeline: () -> Void
    /// Opens the timeline filtered to the entries behind a specific pattern (its tag).
    var onViewEntries: (String) -> Void = { _ in }

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
        .disablesInteractivePop()
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
            // Card + intro + dots are fixed; only the pattern list scrolls, so the
            // horizontal card swipe and vertical scrolling never fight each other.
            VStack(alignment: .leading, spacing: 0) {
                introBlock
                cardStack
                navDots
                ScrollView {
                    historySection
                    Color.clear.frame(height: 12)
                }
                .scrollIndicators(.hidden)
            }
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
            Text("BASED ON YOUR RECORDS")
                .font(.system(size: 10.5, weight: .semibold, design: .default))
                .tracking(0.8)
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            Text("Here are a few consistencies worth your attention.")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // The card sits OUTSIDE the vertical scroll (only the pattern list below scrolls),
    // so a horizontal swipe has no vertical-scroll to fight. highPriority makes the
    // swipe work anywhere on the card (over its buttons) and blocks the edge-back gesture.
    private var cardStack: some View {
        ZStack {
            if index >= insights.count {
                allCaughtUpCard
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset / 20)))
                    .highPriorityGesture(dragGesture)
            } else {
                ForEach(visiblePositions.reversed(), id: \.self) { p in
                    let insight = insights[index + p]
                    InsightCardView(insight: insight, onSupportTap: { onViewEntries(insight.tag) })
                        .scaleEffect(p == 0 ? 1 : (p == 1 ? 0.97 : 0.94))
                        .offset(y: p == 0 ? 0 : (p == 1 ? 8 : 16))
                        .opacity(p == 0 ? 1 : (p == 1 ? 0.85 : 0.6))
                        .offset(x: p == 0 ? dragOffset : 0)
                        .rotationEffect(.degrees(p == 0 ? Double(dragOffset / 20) : 0))
                        .zIndex(Double(3 - p))
                        .highPriorityGesture(p == 0 ? dragGesture : nil)
                }
            }
        }
        // No fixed height: the stack sizes to the current card so a tall card is never
        // clipped, and the pattern list below simply takes the remaining space.
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var visiblePositions: [Int] {
        (0..<3).filter { index + $0 < insights.count }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let w = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let committed = abs(w) > 70 || abs(predicted) > 180
                if committed && w < 0 && index < insights.count {
                    fling(to: -700, then: 1)
                } else if committed && w > 0 && index > 0 {
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

    private var allCaughtUpCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
            Text("All caught up")
                .font(.system(size: 22, weight: .bold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("You've reviewed every pattern. Swipe back to revisit, or see them all listed below.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        // A fixed, comfortable height now that the card stack sizes to content.
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        )
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
                    onView: { onViewEntries(insight.tag) }
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
        // Size to content (no maxHeight) so a tall card — one with a chart and full
        // supporting list — is never forced into a shorter frame and clipped.
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
            TimelineDetailSection(title: "Original notes", text: incident.originalNotes)

            if let analysis = incident.aiAnalysis {
                TimelineDetailSection(
                    title: "AI understanding",
                    text: analysis.understandingSummary.isEmpty ? "Not available" : analysis.understandingSummary.joined(separator: "\n")
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                // Never blank — show a neutral default so the field always reads clearly.
                TimelineDetailRow(
                    label: "Category",
                    value: incident.category.isEmpty ? "Uncategorized" : incident.category,
                    showsSuggestedBadge: incident.categoryWasSuggested
                )
                TimelineDetailRow(label: "People", value: incident.peopleInvolved)
                TimelineDetailRow(label: "Location", value: incident.location)
                TimelineDetailRow(label: "Child involved", value: incident.childInvolved ? "Yes" : "No")
                TimelineDetailRow(label: "Evidence notes", value: incident.evidenceNotes)
            }

            if let analysis = incident.aiAnalysis, !analysis.evidenceMentioned.isEmpty {
                TimelineDetailSection(
                    title: "Evidence mentioned",
                    text: analysis.evidenceMentioned.joined(separator: ", ")
                )
            }

            if !incident.patternTags.isEmpty {
                TimelineDetailSection(
                    title: "Pattern tags",
                    text: incident.patternTags.map(\.displayName).joined(separator: ", ")
                )
            }

            if !incident.followUpQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Follow-up questions")
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
                    Text("User responses")
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
                    Text("Attached photos and screenshots")
                        .font(.subheadline.bold())
                    EvidenceAttachmentGrid(attachments: incident.evidenceAttachments, onRemove: nil)
                }
            }

            // Removed the single-entry "Final Documentation Summary" here: on the
            // court-ready detail view it just restates the notes already shown above.

            if !incident.auditLog.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Change history")
                        .font(.subheadline.bold())
                    ForEach(incident.auditLog) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.action)
                                    .font(.footnote)
                                Text(DateFormatter.factTrailDateTime.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
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
                Label("Edit entry", systemImage: "pencil")
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
    var showsSuggestedBadge: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                if showsSuggestedBadge {
                    SuggestedBadge()
                }
            }
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
