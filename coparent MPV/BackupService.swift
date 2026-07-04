import Foundation

/// A single portable snapshot of everything the app has recorded — every store plus the
/// document files that live outside the JSON. Encodes to one shareable file the user can
/// keep in Files / iCloud Drive, AirDrop, or email to themselves, and restore later. This
/// is the app's durability story until true cloud sync lands: the record survives a
/// reinstall or a new phone.
struct BackupBundle: Codable {
    var schemaVersion: Int
    var exportedAt: Date
    var incidents: [Incident]
    var exchangeRecords: [ExchangeRecord]
    var entries: [Entry]
    var checkIns: [CheckIn]
    var documents: [StoredDocument]
    var linkedNotes: [LinkedNote]
    var files: [BackupFile]

    /// A rough count of user-visible records, for the restore confirmation copy.
    var recordCount: Int {
        incidents.count + exchangeRecords.count + entries.count + checkIns.count + documents.count
    }
}

/// A document file (screenshot, PDF, etc.) carried inline in the backup as raw bytes.
struct BackupFile: Codable {
    var relativePath: String
    var data: Data
}

enum BackupService {
    static let schemaVersion = 1
    static let fileExtension = "coparobackup"

    // MARK: Export

    /// Builds a backup file in a temporary location and returns its URL for sharing.
    static func writeBackup(
        incidents: [Incident],
        exchangeRecords: [ExchangeRecord],
        entries: [Entry],
        checkIns: [CheckIn],
        documents: [StoredDocument],
        linkedNotes: [LinkedNote],
        now: Date
    ) throws -> URL {
        let bundle = BackupBundle(
            schemaVersion: schemaVersion,
            exportedAt: now,
            incidents: incidents,
            exchangeRecords: exchangeRecords,
            entries: entries,
            checkIns: checkIns,
            documents: documents,
            linkedNotes: linkedNotes,
            files: try collectDocumentFiles()
        )

        let data = try encoder.encode(bundle)
        let name = "Coparo Backup \(fileDateString(now)).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: [.atomic])
        return url
    }

    // MARK: Import

    /// Decodes and validates a backup file. Throws a friendly error when the file isn't a
    /// Coparo backup or was made by a newer app version.
    static func readBackup(from url: URL) throws -> BackupBundle {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)
        guard let bundle = try? decoder.decode(BackupBundle.self, from: data) else {
            throw BackupError.notABackup
        }
        guard bundle.schemaVersion <= schemaVersion else {
            throw BackupError.newerSchema
        }
        return bundle
    }

    /// Replaces the document files directory with the files carried in a bundle.
    static func restoreDocumentFiles(_ files: [BackupFile]) throws {
        try? FileManager.default.removeItem(at: DocumentStore.filesDirectory)
        let documentsDir = DocumentStore.documentsDirectory
        for file in files {
            let destination = documentsDir.appendingPathComponent(file.relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: destination, options: [.atomic])
        }
    }

    // MARK: Helpers

    private static func collectDocumentFiles() throws -> [BackupFile] {
        let filesDir = DocumentStore.filesDirectory
        guard FileManager.default.fileExists(atPath: filesDir.path) else { return [] }

        let urls = try FileManager.default.contentsOfDirectory(
            at: filesDir,
            includingPropertiesForKeys: nil
        )
        return try urls.compactMap { url in
            guard !url.hasDirectoryPath else { return nil }
            let data = try Data(contentsOf: url)
            return BackupFile(relativePath: "files/\(url.lastPathComponent)", data: data)
        }
    }

    private static func fileDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    enum BackupError: LocalizedError {
        case notABackup
        case newerSchema

        var errorDescription: String? {
            switch self {
            case .notABackup:
                return "That file isn't a Coparo backup."
            case .newerSchema:
                return "This backup was made by a newer version of Coparo. Update the app and try again."
            }
        }
    }
}
