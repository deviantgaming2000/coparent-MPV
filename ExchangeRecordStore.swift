import Foundation

struct ExchangeRecordStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func loadExchangeRecords() -> [ExchangeRecord] {
        do {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return []
            }

            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder.factTrailExchange.decode([ExchangeRecord].self, from: data)
                .sorted { $0.exchangeDate > $1.exchangeDate }
        } catch {
            return []
        }
    }

    func saveExchangeRecords(_ records: [ExchangeRecord]) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.factTrailExchange.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }

    /// Removes the persisted store so the next load returns a clean, empty slate.
    func deleteAll() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("facttrail-exchange-records.json")
    }
}

private extension JSONEncoder {
    static var factTrailExchange: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var factTrailExchange: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
