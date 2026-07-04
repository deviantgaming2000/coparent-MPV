
import Foundation

struct IncidentStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func loadIncidents() -> [Incident] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder.factTrail.decode([Incident].self, from: data)
                .sorted { $0.incidentDate > $1.incidentDate }
        } catch {
            return []
        }
    }

    func saveIncidents(_ incidents: [Incident]) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.factTrail.encode(incidents)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Removes the persisted store so the next load returns a clean, empty slate.
    func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("facttrail-incidents.json")
    }
}

private extension JSONEncoder {
    static var factTrail: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var factTrail: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
