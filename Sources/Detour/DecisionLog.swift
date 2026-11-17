import Foundation
import DetourCore

enum DecisionLog {
    struct Entry: Codable {
        var time: Date
        var host: String
        var sourceApp: String?
        var target: String?
        var stage: String
        var asked: Bool
    }

    private static let queue = DispatchQueue(label: "detour.log")
    private static let retention: TimeInterval = 90 * 86_400

    static func append(_ entry: Entry) {
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard var line = try? encoder.encode(entry) else { return }
            line.append(0x0A)
            let url = Paths.decisions
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? line.write(to: url)
            }
        }
    }

    static func readAll() -> [Entry] {
        guard let data = try? Data(contentsOf: Paths.decisions) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(Entry.self, from: Data($0)) }
    }

    static let resetsKey = "appLearningResets"

    static func tendencies() -> AppTendencies {
        let resets = (UserDefaults.standard.dictionary(forKey: resetsKey) as? [String: Date]) ?? [:]
        return AppTendencies(entries: readAll().compactMap { entry in
            guard let app = entry.sourceApp, let target = entry.target, let stage = Stage(rawValue: entry.stage) else { return nil }
            if let reset = resets[app.lowercased()], entry.time <= reset { return nil }
            return AppTendencies.Entry(app: app, target: target, stage: stage)
        })
    }

    static func prune(now: Date = Date()) {
        queue.async {
            guard let data = try? Data(contentsOf: Paths.decisions) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cutoff = now.addingTimeInterval(-retention)
            let kept = data.split(separator: 0x0A).filter { line in
                guard let entry = try? decoder.decode(Entry.self, from: Data(line)) else { return false }
                return entry.time >= cutoff
            }
            var out = Data()
            for line in kept { out.append(contentsOf: line); out.append(0x0A) }
            try? out.write(to: Paths.decisions, options: .atomic)
        }
    }
}
