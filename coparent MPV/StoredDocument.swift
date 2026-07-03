import Foundation
import UniformTypeIdentifiers

struct StoredDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fileName: String
    var fileType: DocumentFileType
    var category: DocumentCategory
    var createdAt: Date
    var importedAt: Date
    var notes: String?
    var tags: [EntryTag]
    var linkedTimelineItemIds: [String]
    var localFilePath: String?
    var thumbnailData: Data?
    var isFlagged: Bool

    init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        fileType: DocumentFileType,
        category: DocumentCategory,
        createdAt: Date = Date(),
        importedAt: Date = Date(),
        notes: String? = nil,
        tags: [EntryTag] = [],
        linkedTimelineItemIds: [String] = [],
        localFilePath: String? = nil,
        thumbnailData: Data? = nil,
        isFlagged: Bool = false
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileType = fileType
        self.category = category
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.notes = notes
        self.tags = tags
        self.linkedTimelineItemIds = linkedTimelineItemIds
        self.localFilePath = localFilePath
        self.thumbnailData = thumbnailData
        self.isFlagged = isFlagged
    }

    var localFileURL: URL? {
        guard let localFilePath else { return nil }
        return DocumentStore.documentsDirectory.appendingPathComponent(localFilePath)
    }
}

enum DocumentFileType: String, Codable, CaseIterable {
    case image
    case pdf
    case text
    case other

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .text: return "Text"
        case .other: return "File"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }

    static func inferred(from utType: UTType?, fileExtension: String?) -> DocumentFileType {
        if let utType {
            if utType.conforms(to: .image) { return .image }
            if utType.conforms(to: .pdf) { return .pdf }
            if utType.conforms(to: .text) || utType.conforms(to: .plainText) { return .text }
        }
        if let ext = fileExtension?.lowercased() {
            switch ext {
            case "png", "jpg", "jpeg", "heic", "gif", "tif", "tiff", "bmp", "webp":
                return .image
            case "pdf":
                return .pdf
            case "txt", "md", "rtf":
                return .text
            default:
                return .other
            }
        }
        return .other
    }
}

enum DocumentCategory: String, Codable, CaseIterable, Identifiable {
    case court
    case school
    case medical
    case therapy
    case exchange
    case communication
    case receipt
    case screenshot
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .court: return "Court"
        case .school: return "School"
        case .medical: return "Medical"
        case .therapy: return "Therapy"
        case .exchange: return "Exchange"
        case .communication: return "Communication"
        case .receipt: return "Receipt"
        case .screenshot: return "Screenshot"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .court: return "building.columns"
        case .school: return "graduationcap"
        case .medical: return "cross.case"
        case .therapy: return "heart.text.square"
        case .exchange: return "arrow.left.arrow.right"
        case .communication: return "bubble.left.and.bubble.right"
        case .receipt: return "receipt"
        case .screenshot: return "text.bubble"
        case .other: return "folder"
        }
    }
}

enum DocumentSortOrder: String, CaseIterable, Identifiable {
    case recentlyAdded
    case oldestFirst
    case titleAZ
    case category

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .recentlyAdded: return "Recently added"
        case .oldestFirst: return "Oldest first"
        case .titleAZ: return "Title (A-Z)"
        case .category: return "Category"
        }
    }
}
