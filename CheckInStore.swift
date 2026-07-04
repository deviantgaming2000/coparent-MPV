import Foundation

struct CheckInStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func loadCheckIns() -> [CheckIn] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder.coDoc.decode([CheckIn].self, from: data)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    func saveCheckIns(_ checkIns: [CheckIn]) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.coDoc.encode(checkIns)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Removes the persisted store so the next load returns a clean, empty slate.
    func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("codoc-check-ins.json")
    }
}
