import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

/// The reference groups documents into three visual types (screenshot / photo / file),
/// each with its own tint, independent of the richer semantic `DocumentCategory`.
enum DocReferenceType {
    case screenshot, photo, file

    var label: String {
        switch self {
        case .screenshot: return "Screenshot"
        case .photo: return "Photo"
        case .file: return "File"
        }
    }

    var color: Color {
        switch self {
        case .screenshot: return Color(red: 0x4F / 255, green: 0x8F / 255, blue: 0x8B / 255)
        case .photo: return Color(red: 0x2F / 255, green: 0x5D / 255, blue: 0x8C / 255)
        case .file: return Color(red: 0x05 / 255, green: 0x96 / 255, blue: 0x69 / 255)
        }
    }

    var systemImage: String {
        switch self {
        case .screenshot: return "text.bubble"
        case .photo: return "photo"
        case .file: return "doc"
        }
    }

    static func classify(_ document: StoredDocument) -> DocReferenceType {
        if document.category == .screenshot { return .screenshot }
        if document.fileType == .image { return .photo }
        return .file
    }
}

private enum DocSortMode {
    case date, name
}

private enum DocTypeFilter: CaseIterable, Identifiable {
    case all, screenshots, photos, files, standalone

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "All"
        case .screenshots: return "Screenshots"
        case .photos: return "Photos"
        case .files: return "Files"
        case .standalone: return "Standalone"
        }
    }

    var referenceType: DocReferenceType? {
        switch self {
        case .screenshots: return .screenshot
        case .photos: return .photo
        case .files: return .file
        case .all, .standalone: return nil
        }
    }
}

struct MyDocumentsView: View {
    let documents: [StoredDocument]
    let onAddDocument: (StoredDocument) -> Void
    let onUpdateDocument: (StoredDocument) -> Void
    let onDeleteDocument: (StoredDocument) -> Void
    var onTimeline: () -> Void = {}
    var onInsights: () -> Void = {}
    var linkedEntryTitle: (StoredDocument) -> String? = { _ in nil }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var sortMode: DocSortMode = .date
    @State private var typeFilter: DocTypeFilter = .all
    @State private var isShowingAddSheet = false
    @State private var detailDocument: StoredDocument?

    private var filteredDocuments: [StoredDocument] {
        var docs = documents

        switch typeFilter {
        case .all:
            break
        case .standalone:
            docs = docs.filter { $0.linkedTimelineItemIds.isEmpty }
        case .screenshots, .photos, .files:
            docs = docs.filter { DocReferenceType.classify($0) == typeFilter.referenceType }
        }

        switch sortMode {
        case .date:
            docs.sort { $0.importedAt > $1.importedAt }
        case .name:
            docs.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        return docs
    }

    /// Filtered documents grouped by month, preserving the date-sorted order, for the
    /// reference's "JULY 2026" month headers. Only used when sorting by date.
    private var monthGroups: [(label: String, docs: [StoredDocument])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var order: [String] = []
        var buckets: [String: [StoredDocument]] = [:]
        for doc in filteredDocuments {
            let key = formatter.string(from: doc.importedAt)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(doc)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if documents.isEmpty {
                emptyState
            } else {
                controls

                if filteredDocuments.isEmpty {
                    filteredEmptyState
                } else {
                    documentList
                }
            }

            HomeBottomNavigation(
                activeTab: .documents,
                onHome: { dismiss() },
                onTimeline: onTimeline,
                onInsights: onInsights
            )
        }
        .factTrailScreenBackground()
        .navigationTitle("My documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingAddSheet) {
            AddDocumentSheet { newDocument in
                onAddDocument(newDocument)
                isShowingAddSheet = false
            } onCancel: {
                isShowingAddSheet = false
            }
        }
        .sheet(item: $detailDocument) { document in
            DocumentDetailView(
                document: document,
                onUpdate: { updated in
                    onUpdateDocument(updated)
                    detailDocument = updated
                },
                onDelete: { toDelete in
                    onDeleteDocument(toDelete)
                    detailDocument = nil
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                dismiss()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 17, weight: .medium, design: .default))
            }
            .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))

            Spacer()

            Text("My documents")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            Spacer()

            Button {
                isShowingAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            }
            .accessibilityLabel("Add document")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("Sort by")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

                Spacer()

                HStack(spacing: 3) {
                    sortButton(.date, label: "Date")
                    sortButton(.name, label: "Name")
                }
                .padding(3)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(FactTrailTheme.border(for: colorScheme).opacity(0.5))
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(DocTypeFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func sortButton(_ mode: DocSortMode, label: String) -> some View {
        let isActive = sortMode == mode
        return Button {
            sortMode = mode
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(isActive ? FactTrailTheme.primaryText(for: colorScheme) : FactTrailTheme.mutedText(for: colorScheme))
                .padding(.vertical, 5)
                .padding(.horizontal, 11)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? FactTrailTheme.surface(for: colorScheme) : Color.clear)
                        .shadow(color: isActive ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ filter: DocTypeFilter) -> some View {
        let isActive = typeFilter == filter
        let accent = FactTrailTheme.aiAccent(for: colorScheme)
        return Button {
            typeFilter = filter
        } label: {
            Text(filter.label)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundStyle(isActive ? accent : FactTrailTheme.secondaryText(for: colorScheme))
                .padding(.vertical, 6)
                .padding(.horizontal, 13)
                .background(
                    Capsule().fill(isActive ? accent.opacity(0.10) : FactTrailTheme.surface(for: colorScheme))
                )
                .overlay {
                    Capsule().stroke(isActive ? accent : FactTrailTheme.border(for: colorScheme), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }

    private var documentList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if sortMode == .date {
                    ForEach(monthGroups, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.label.uppercased())
                                .font(.system(size: 10.5, weight: .semibold, design: .default))
                                .tracking(0.7)
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                                .padding(.leading, 2)

                            ForEach(group.docs) { document in
                                documentRow(document)
                            }
                        }
                        .padding(.bottom, 18)
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredDocuments) { document in
                            documentRow(document)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }

    private func documentRow(_ document: StoredDocument) -> some View {
        Button {
            detailDocument = document
        } label: {
            DocumentRow(document: document, linkedTitle: linkedEntryTitle(document))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            Text("No documents yet")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Add screenshots, files, and supporting records so they're easy to find when you need them.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                isShowingAddSheet = true
            } label: {
                Label("Add document", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            Text("No documents match this filter yet")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Try a different filter.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DocumentRow: View {
    let document: StoredDocument
    let linkedTitle: String?
    @Environment(\.colorScheme) private var colorScheme

    private var type: DocReferenceType { DocReferenceType.classify(document) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(type.color.opacity(0.12))
                Image(systemName: type.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(type.color)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(document.title)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                    if document.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Text(type.label.uppercased())
                        .font(.system(size: 9.5, weight: .semibold, design: .default))
                        .tracking(0.4)
                        .foregroundStyle(type.color)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(Capsule().fill(type.color.opacity(0.12)))

                    if let linkedTitle {
                        Text("Linked · \(linkedTitle)")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                            .lineLimit(1)
                    } else {
                        Text("Standalone — no linked entry")
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .italic()
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme).opacity(0.35))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
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
}

// MARK: - Add Document Sheet

struct AddDocumentSheet: View {
    let onSave: (StoredDocument) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var title: String = ""
    @State private var category: DocumentCategory = .other
    @State private var notes: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoSuggestedName: String = ""
    @State private var pickedFileURL: URL?
    @State private var pickedFileName: String = ""
    @State private var isShowingFileImporter = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let documentStore = DocumentStore()

    private var hasSource: Bool {
        photoData != nil || pickedFileURL != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourcePickerSection
                    if hasSource {
                        detailsSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }
            .factTrailScreenBackground()
            .navigationTitle("Add document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!hasSource || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                Task { await loadPhoto(from: newValue) }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .text, .rtf, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        pickedFileURL = url
                        pickedFileName = url.lastPathComponent
                        photoData = nil
                        selectedPhoto = nil
                        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            title = url.deletingPathExtension().lastPathComponent
                        }
                        if category == .other {
                            category = defaultCategory(for: url)
                        }
                    }
                case .failure(let error):
                    errorMessage = "Could not import file: \(error.localizedDescription)"
                }
            }
        }
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose source")
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    sourceButtonLabel(title: "Photo", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)

                Button {
                    isShowingFileImporter = true
                } label: {
                    sourceButtonLabel(title: "File", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }

            if let photoData, let uiImage = UIImage(data: photoData) {
                selectedSourcePreview {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else if let pickedFileURL {
                selectedSourcePreview {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(pickedFileURL.lastPathComponent, systemImage: "doc.text")
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Text(pickedFileURL.pathExtension.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
            }
        }
    }

    private func sourceButtonLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FactTrailTheme.primaryAction(for: colorScheme))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
    }

    private func selectedSourcePreview<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(maxHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
            }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                TextField("e.g. School email June 3", text: $title)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FactTrailTheme.surface(for: colorScheme))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Category")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                Menu {
                    ForEach(DocumentCategory.allCases) { option in
                        Button {
                            category = option
                        } label: {
                            Label(option.displayName, systemImage: option.systemImage)
                        }
                    }
                } label: {
                    HStack {
                        Label(category.displayName, systemImage: category.systemImage)
                            .font(.system(size: 14, weight: .semibold, design: .default))
                            .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FactTrailTheme.surface(for: colorScheme))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                TextEditor(text: $notes)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(FactTrailTheme.surface(for: colorScheme))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                    }
            }
        }
    }

    private func loadPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    photoData = data
                    pickedFileURL = nil
                    pickedFileName = ""
                    photoSuggestedName = "screenshot-\(Int(Date().timeIntervalSince1970))"
                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = photoSuggestedName
                    }
                    if category == .other {
                        category = .screenshot
                    }
                    errorMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not load photo: \(error.localizedDescription)"
            }
        }
    }

    private func defaultCategory(for url: URL) -> DocumentCategory {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return .other
        case "png", "jpg", "jpeg": return .screenshot
        default: return .other
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        do {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            var relativePath: String?
            var fileName: String = ""
            var fileType: DocumentFileType = .other
            var thumbnail: Data? = nil

            if let photoData {
                let base = trimmedTitle.isEmpty ? photoSuggestedName : trimmedTitle
                relativePath = try documentStore.importData(photoData, suggestedName: base, fileExtension: "jpg")
                fileName = URL(fileURLWithPath: relativePath ?? "").lastPathComponent
                fileType = .image
                thumbnail = makeThumbnail(from: photoData)
            } else if let pickedFileURL {
                let ut = try? pickedFileURL.resourceValues(forKeys: [.contentTypeKey]).contentType
                fileType = DocumentFileType.inferred(from: ut, fileExtension: pickedFileURL.pathExtension)
                relativePath = try documentStore.importFile(from: pickedFileURL, suggestedName: trimmedTitle.isEmpty ? nil : trimmedTitle)
                fileName = URL(fileURLWithPath: relativePath ?? "").lastPathComponent
                if fileType == .image, let data = try? Data(contentsOf: pickedFileURL) {
                    thumbnail = makeThumbnail(from: data)
                }
            }

            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let document = StoredDocument(
                title: trimmedTitle,
                fileName: fileName,
                fileType: fileType,
                category: category,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                localFilePath: relativePath,
                thumbnailData: thumbnail
            )
            onSave(document)
        } catch {
            errorMessage = "Could not save document: \(error.localizedDescription)"
        }

        isSaving = false
    }

    private func makeThumbnail(from data: Data) -> Data? {
        guard let uiImage = UIImage(data: data) else { return nil }
        let maxDim: CGFloat = 200
        let aspect = uiImage.size.width / max(uiImage.size.height, 1)
        let targetSize: CGSize
        if aspect >= 1 {
            targetSize = CGSize(width: maxDim, height: maxDim / aspect)
        } else {
            targetSize = CGSize(width: maxDim * aspect, height: maxDim)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let scaled = renderer.image { _ in
            uiImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return scaled.jpegData(compressionQuality: 0.7)
    }
}

// MARK: - Document Detail

struct DocumentDetailView: View {
    let document: StoredDocument
    let onUpdate: (StoredDocument) -> Void
    let onDelete: (StoredDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isEditing = false
    @State private var editableTitle: String
    @State private var editableCategory: DocumentCategory
    @State private var editableNotes: String
    @State private var isFlagged: Bool
    @State private var isShowingDeleteConfirm = false
    @State private var quickLookURL: URL?

    init(document: StoredDocument, onUpdate: @escaping (StoredDocument) -> Void, onDelete: @escaping (StoredDocument) -> Void) {
        self.document = document
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _editableTitle = State(initialValue: document.title)
        _editableCategory = State(initialValue: document.category)
        _editableNotes = State(initialValue: document.notes ?? "")
        _isFlagged = State(initialValue: document.isFlagged)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                    metadata
                    Divider()
                    actions
                }
                .padding(20)
            }
            .factTrailScreenBackground()
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Save") {
                            var updated = document
                            updated.title = editableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.category = editableCategory
                            let trimmedNotes = editableNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
                            updated.isFlagged = isFlagged
                            onUpdate(updated)
                            isEditing = false
                        }
                        .fontWeight(.semibold)
                        .disabled(editableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
            .quickLookPreview($quickLookURL)
            .alert("Delete this document?", isPresented: $isShowingDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    onDelete(document)
                    dismiss()
                }
            } message: {
                Text("The file and its metadata will be removed. This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if document.fileType == .image, let url = document.localFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
        } else if let url = document.localFileURL {
            Button {
                quickLookURL = url
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: document.fileType.systemImage)
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                    Text(document.fileName)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                    Text("Tap to preview")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(28)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                Text("File not found")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if isEditing {
            VStack(alignment: .leading, spacing: 14) {
                labeled("Title") {
                    TextField("Title", text: $editableTitle)
                        .textFieldStyle(.plain)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                }
                labeled("Category") {
                    Menu {
                        ForEach(DocumentCategory.allCases) { option in
                            Button {
                                editableCategory = option
                            } label: {
                                Label(option.displayName, systemImage: option.systemImage)
                            }
                        }
                    } label: {
                        HStack {
                            Label(editableCategory.displayName, systemImage: editableCategory.systemImage)
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        }
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                    }
                }
                labeled("Notes") {
                    TextEditor(text: $editableNotes)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                }
                Toggle(isOn: $isFlagged) {
                    Label("Flag as important", systemImage: "flag")
                        .font(.system(size: 14, weight: .semibold, design: .default))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                    if document.isFlagged {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    Label(document.category.displayName, systemImage: document.category.systemImage)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(Capsule().fill(FactTrailTheme.aiSoftBackground(for: colorScheme)))
                    Label(document.fileType.displayName, systemImage: document.fileType.systemImage)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(Capsule().fill(FactTrailTheme.surface(for: colorScheme)))
                        .overlay { Capsule().stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1) }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Imported")
                        .font(.caption).foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    Text(DateFormatter.factTrailDateTime.string(from: document.importedAt))
                        .font(.footnote).foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                }

                if let notes = document.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption).foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                        Text(notes)
                            .font(.footnote).foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("File name")
                        .font(.caption).foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    Text(document.fileName)
                        .font(.footnote).foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                }
            }
        }
    }

    private func labeled<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            content()
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
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
                Label("Delete document", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailGlassButtonStyle())
        }
    }
}
