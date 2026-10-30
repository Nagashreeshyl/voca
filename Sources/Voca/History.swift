import Foundation

struct HistoryEntry: Codable {
    let id: UUID
    let date: Date
    var transcript: String?
    var output: String?
    var intent: String?
    var provider: String?
    var error: String?

    var audio: URL { History.audioDir.appendingPathComponent("\(id.uuidString).m4a") }
}

/// Dictations from the last 24 hours with their audio, so a failed one can be retried.
final class History {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Voca")
    static let audioDir = dir.appendingPathComponent("audio")
    static let retention: TimeInterval = 24 * 60 * 60
    private let file = dir.appendingPathComponent("history.json")
    private(set) var entries: [HistoryEntry] = [] // newest first

    init() {
        try? FileManager.default.createDirectory(at: Self.audioDir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            entries = (try? dec.decode([HistoryEntry].self, from: data)) ?? []
        }
        prune()
    }

    /// Deletes entries and audio older than 24 hours.
    func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let old = entries.filter { $0.date < cutoff }
        guard !old.isEmpty else { return }
        for e in old { try? FileManager.default.removeItem(at: e.audio) }
        entries.removeAll { $0.date < cutoff }
        save()
    }

    /// Moves the recording into history and returns the new entry.
    func add(recording: URL) -> HistoryEntry {
        let e = HistoryEntry(id: UUID(), date: Date())
        try? FileManager.default.moveItem(at: recording, to: e.audio)
        entries.insert(e, at: 0)
        save()
        prune()
        return e
    }

    func update(_ e: HistoryEntry) {
        guard let i = entries.firstIndex(where: { $0.id == e.id }) else { return }
        entries[i] = e
        save()
    }

    func clear() {
        for e in entries { try? FileManager.default.removeItem(at: e.audio) }
        entries = []
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(entries).write(to: file, options: .atomic)
    }
}
