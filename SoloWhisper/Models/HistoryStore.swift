import Foundation

struct HistoryFile: Codable {
    var version: Int = 1
    var records: [TranscriptionRecord] = []
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published var records: [TranscriptionRecord] = []

    private let maxRecords = 500

    private var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SoloWhisper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        records = load()
    }

    func add(_ record: TranscriptionRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    func clearAll() {
        records = []
        save()
    }

    private func load() -> [TranscriptionRecord] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(HistoryFile.self, from: data)
            return file.records
        } catch {
            // Backup corrupted file
            let backupURL = url.deletingLastPathComponent().appendingPathComponent("history.json.bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: url, to: backupURL)
            print("⚠️ History file corrupted, backed up to history.json.bak")
            return []
        }
    }

    private func save() {
        let file = HistoryFile(version: 1, records: records)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
