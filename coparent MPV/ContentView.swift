import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @AppStorage("hasAcceptedFactTrailDisclaimer") private var hasAcceptedDisclaimer = false
    @State private var incidents: [Incident] = []
    @State private var path: [AppRoute] = []
    @State private var pendingSummary: IncidentSummaryDraft?
    @State private var saveErrorMessage: String?

    private let incidentStore = IncidentStore()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hasAcceptedDisclaimer {
                    HomeView(
                        incidentCount: incidents.count,
                        onDocumentSomething: { path.append(.entry) },
                        onViewTimeline: { path.append(.timeline) }
                    )
                } else {
                    OnboardingView {
                        hasAcceptedDisclaimer = true
                    }
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .entry:
                    IncidentEntryView { summary in
                        pendingSummary = summary
                        path.append(.review)
                    }
                case .review:
                    if let pendingSummary {
                        SummaryReviewView(
                            summaryDraft: pendingSummary,
                            onSave: {
                                saveIncident(pendingSummary.incident)
                                self.pendingSummary = nil
                                path.removeAll()
                            },
                            onEdit: {
                                path.removeLast()
                            },
                            onCancel: {
                                self.pendingSummary = nil
                                path.removeAll()
                            }
                        )
                    } else {
                        ContentUnavailableView("No Summary", systemImage: "doc.text.magnifyingglass")
                    }
                case .timeline:
                    TimelineView(incidents: incidents, saveErrorMessage: saveErrorMessage)
                }
            }
        }
        .onAppear {
            incidents = incidentStore.loadIncidents()
        }
    }

    private func saveIncident(_ incident: Incident) {
        incidents.insert(incident, at: 0)

        do {
            try incidentStore.saveIncidents(incidents)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Incident could not be saved on this device."
        }
    }
}

private enum AppRoute: Hashable {
    case entry
    case review
    case timeline
}

private struct OnboardingView: View {
    let onAccept: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FactTrail")
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
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
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

private struct HomeView: View {
    let incidentCount: Int
    let onDocumentSomething: () -> Void
    let onViewTimeline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FactTrail")
                    .font(.largeTitle.bold())
                Text("When something happens, start here. Talk naturally. The app will help organize the facts.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                Button(action: onDocumentSomething) {
                    Label("Document Something", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onViewTimeline) {
                    Label("View Timeline", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if incidentCount > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Activity")
                        .font(.headline)
                    Text("\(incidentCount) saved incident\(incidentCount == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IncidentEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = IncidentDraft()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isLoadingAttachments = false
    @State private var attachmentErrorMessage: String?

    let onCreateSummary: (IncidentSummaryDraft) -> Void

    var body: some View {
        Form {
            Section("What happened?") {
                TextEditor(text: $draft.originalNotes)
                    .frame(minHeight: 150)
                    .overlay(alignment: .topLeading) {
                        if draft.originalNotes.isEmpty {
                            Text("Describe the event in your own words.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Section("Details") {
                DatePicker("Approximate date/time", selection: $draft.incidentDate)

                TextField("People involved", text: $draft.peopleInvolved, axis: .vertical)
                    .lineLimit(1...3)

                TextField("Location", text: $draft.location, axis: .vertical)
                    .lineLimit(1...3)

                Toggle("Child involved?", isOn: $draft.childInvolved)

                Picker("Category", selection: $draft.category) {
                    ForEach(IncidentCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
            }

            Section("Supporting evidence notes") {
                TextEditor(text: $draft.evidenceNotes)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if draft.evidenceNotes.isEmpty {
                            Text("Screenshots, call logs, emails, records, photos, or other notes.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                            }
                    }

                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 6,
                    matching: .images
                ) {
                    Label("Add Photos or Screenshots", systemImage: "photo.on.rectangle.angled")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if isLoadingAttachments {
                    HStack {
                        ProgressView()
                        Text("Adding selected images...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let attachmentErrorMessage {
                    Text(attachmentErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if !draft.evidenceAttachments.isEmpty {
                    EvidenceAttachmentGrid(
                        attachments: draft.evidenceAttachments,
                        onRemove: removeAttachment
                    )
                    .padding(.top, 4)
                }
            }

            Section {
                Button {
                    onCreateSummary(NeutralSummaryGenerator.makeSummary(from: draft))
                } label: {
                    Text("Create Neutral Summary")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!draft.canCreateSummary)
            }
        }
        .navigationTitle("Document Something")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await loadAttachments(from: newItems)
            }
        }
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
                ReviewSection(title: "Neutral Summary", text: summaryDraft.neutralSummary)

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

                VStack(spacing: 12) {
                    if let pdfURL {
                        ShareLink(
                            item: pdfURL,
                            subject: Text("FactTrail Summary"),
                            message: Text("FactTrail documentation summary")
                        ) {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(action: onEdit) {
                        Label("Edit Entry", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(role: .cancel, action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding(20)
        }
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

private struct TimelineView: View {
    let incidents: [Incident]
    let saveErrorMessage: String?
    @State private var expandedIncidentIDs: Set<UUID> = []

    var body: some View {
        Group {
            if incidents.isEmpty {
                ContentUnavailableView(
                    "No Incidents Saved",
                    systemImage: "calendar.badge.clock",
                    description: Text("Saved summaries will appear here as a timeline.")
                )
            } else {
                List(incidents) { incident in
                    IncidentCardView(
                        incident: incident,
                        isExpanded: expandedIncidentIDs.contains(incident.id),
                        onToggle: {
                            toggleIncident(incident)
                        }
                    )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private func toggleIncident(_ incident: Incident) {
        withAnimation(.snappy) {
            if expandedIncidentIDs.contains(incident.id) {
                expandedIncidentIDs.remove(incident.id)
            } else {
                expandedIncidentIDs.insert(incident.id)
            }
        }
    }
}

private struct IncidentCardView: View {
    let incident: Incident
    let isExpanded: Bool
    let onToggle: () -> Void

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
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                IncidentExpandedDetailsView(incident: incident)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryPreview: String {
        incident.neutralSummary
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TimelineDetailSection(title: "Neutral Summary", text: incident.neutralSummary)
            TimelineDetailSection(title: "Original Notes", text: incident.originalNotes)

            VStack(alignment: .leading, spacing: 8) {
                TimelineDetailRow(label: "People", value: incident.peopleInvolved)
                TimelineDetailRow(label: "Location", value: incident.location)
                TimelineDetailRow(label: "Child involved", value: incident.childInvolved ? "Yes" : "No")
                TimelineDetailRow(label: "Evidence notes", value: incident.evidenceNotes)
            }

            if !incident.evidenceAttachments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Attached Photos and Screenshots")
                        .font(.subheadline.bold())
                    EvidenceAttachmentGrid(attachments: incident.evidenceAttachments, onRemove: nil)
                }
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

            TimelinePDFShareButton(incident: incident)
        }
        .padding(.top, 4)
    }
}

private struct TimelineDetailSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            Text(displayValue)
                .font(.footnote)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayValue)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayValue: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not specified" : trimmed
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
                    subject: Text("FactTrail Summary"),
                    message: Text("FactTrail documentation summary")
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
