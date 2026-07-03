import Foundation

struct DocumentStore {
    private let metadataURL: URL

    init(metadataURL: URL? = nil) {
        self.metadataURL = metadataURL ?? Self.defaultMetadataURL
    }

    func loadDocuments() -> [StoredDocument] {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: metadataURL)
            return try JSONDecoder.coDoc.decode([StoredDocument].self, from: data)
                .sorted { $0.importedAt > $1.importedAt }
        } catch {
            return []
        }
    }

    func saveDocuments(_ documents: [StoredDocument]) throws {
        let folderURL = metadataURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.coDoc.encode(documents)
        try data.write(to: metadataURL, options: [.atomic])
    }

    /// Copies a source file into the app's storage folder and returns the relative filename.
    func importFile(from sourceURL: URL, suggestedName: String? = nil) throws -> String {
        let filesFolder = Self.filesDirectory
        try FileManager.default.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension
        let base = suggestedName?.replacingOccurrences(of: "/", with: "-") ?? sourceURL.deletingPathExtension().lastPathComponent
        let safeBase = base.isEmpty ? UUID().uuidString : base
        let uniqueName: String
        if ext.isEmpty {
            uniqueName = "\(safeBase)-\(UUID().uuidString.prefix(6))"
        } else {
            uniqueName = "\(safeBase)-\(UUID().uuidString.prefix(6)).\(ext)"
        }

        let destinationURL = filesFolder.appendingPathComponent(uniqueName)

        let needsSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        return "files/\(uniqueName)"
    }

    /// Persists raw data (e.g. a picked photo) to the storage folder and returns the relative path.
    func importData(_ data: Data, suggestedName: String, fileExtension: String) throws -> String {
        let filesFolder = Self.filesDirectory
        try FileManager.default.createDirectory(at: filesFolder, withIntermediateDirectories: true)

        let safeBase = suggestedName.replacingOccurrences(of: "/", with: "-")
        let base = safeBase.isEmpty ? UUID().uuidString : safeBase
        let uniqueName = "\(base)-\(UUID().uuidString.prefix(6)).\(fileExtension)"
        let destinationURL = filesFolder.appendingPathComponent(uniqueName)

        try data.write(to: destinationURL, options: [.atomic])
        return "files/\(uniqueName)"
    }

    func deleteFile(atRelativePath relativePath: String) {
        let url = Self.documentsDirectory.appendingPathComponent(relativePath)
        try? FileManager.default.removeItem(at: url)
    }

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var filesDirectory: URL {
        documentsDirectory.appendingPathComponent("files", isDirectory: true)
    }

    private static var defaultMetadataURL: URL {
        documentsDirectory.appendingPathComponent("codoc-documents.json")
    }
}
