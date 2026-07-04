import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct MyDocumentsView: View {
    let documents: [StoredDocument]
    let onAddDocument: (StoredDocument) -> Void
    let onUpdateDocument: (StoredDocument) -> Void
    let onDeleteDocument: (StoredDocument) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: DocumentCategory? = nil
    @State private var sortOrder: DocumentSortOrder = .recentlyAdded
    @State private var isShowingAddSheet = false
    @State private var detailDocument: StoredDocument?

    private var filteredDocuments: [StoredDocument] {
        var docs = documents

        if let selectedCategory {
            docs = docs.filter { $0.category == selectedCategory }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            docs = docs.filter { document in
                let haystack = [
                    document.title,
                    document.fileName,
                    document.notes ?? "",
                    document.category.displayName,
                    document.tags.map(\.displayName).joined(separator: " ")
                ].joined(separator: " ").lowercased()
                return haystack.contains(trimmed)
            }
        }

        switch sortOrder {
        case .recentlyAdded:
            docs.sort { $0.importedAt > $1.importedAt }
        case .oldestFirst:
            docs.sort { $0.importedAt < $1.importedAt }
        case .titleAZ:
            docs.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .category:
            docs.sort { $0.category.displayName < $1.category.displayName }
        }

        return docs
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if documents.isEmpty {
                emptyState
            } else {
                filterBar

                if filteredDocuments.isEmpty {
                    filteredEmptyState
                } else {
                    documentList
                }
            }
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

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                TextField("Search documents", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(FactTrailTheme.surface(for: colorScheme))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
            }

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        categoryChip(nil, label: "All")
                        ForEach(DocumentCategory.allCases) { category in
                            categoryChip(category, label: category.displayName)
                        }
                    }
                }

                Menu {
                    ForEach(DocumentSortOrder.allCases) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.displayName, systemImage: "checkmark")
                            } else {
                                Text(order.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule().fill(FactTrailTheme.surface(for: colorScheme))
                        )
                        .overlay {
                            Capsule().stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func categoryChip(_ category: DocumentCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(isSelected ? FactTrailTheme.background(for: colorScheme) : FactTrailTheme.primaryText(for: colorScheme))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    Capsule().fill(isSelected ? FactTrailTheme.primaryAction(for: colorScheme) : FactTrailTheme.surface(for: colorScheme))
                )
                .overlay {
                    Capsule().stroke(FactTrailTheme.border(for: colorScheme), lineWidth: isSelected ? 0 : 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var documentList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredDocuments) { document in
                    Button {
                        detailDocument = document
                    } label: {
                        DocumentRow(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
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
            Text("No matching documents")
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
            Text("Try clearing the search or filter.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DocumentRow: View {
    let document: StoredDocument
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(document.title)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                        .lineLimit(2)
                    if document.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 6) {
                    Label(document.category.displayName, systemImage: document.category.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule().fill(FactTrailTheme.aiSoftBackground(for: colorScheme))
                        )
                    Text(DateFormatter.factTrailDateTime.string(from: document.importedAt))
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }

                if let notes = document.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FactTrailTheme.surface(for: colorScheme))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = document.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if document.fileType == .image, let url = document.localFileURL, let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: document.fileType.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))
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
