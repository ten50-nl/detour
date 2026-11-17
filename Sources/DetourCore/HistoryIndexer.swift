import Foundation

public struct HistorySource: Sendable {
    public enum Kind: Sendable { case chrome, firefox }

    public var target: DestinationID
    public var kind: Kind
    public var dbPath: URL

    public init(target: DestinationID, kind: Kind, dbPath: URL) {
        self.target = target
        self.kind = kind
        self.dbPath = dbPath
    }
}

public struct HistoryIndexer: Sendable {
    public static let windowDays: Double = 90

    public var cacheDir: URL

    public init(cacheDir: URL) {
        self.cacheDir = cacheDir
    }

    public func build(sources: [HistorySource], now: Date) throws -> HistoryIndex {
        var index = HistoryIndex(builtAt: now)
        let since = now.addingTimeInterval(-Self.windowDays * 86_400).timeIntervalSince1970
        let fm = FileManager.default
        try fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        for leftover in (try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: leftover)
        }
        for source in sources where fm.fileExists(atPath: source.dbPath.path) {
            let copy = cacheDir.appendingPathComponent("\(UUID().uuidString)-\(source.dbPath.lastPathComponent)")
            for suffix in ["", "-wal"] {
                let from = URL(fileURLWithPath: source.dbPath.path + suffix)
                let to = URL(fileURLWithPath: copy.path + suffix)
                try? fm.removeItem(at: to)
                if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: to) }
            }
            defer {
                for suffix in ["", "-wal", "-shm"] { try? fm.removeItem(atPath: copy.path + suffix) }
            }
            let urls: [String]
            switch source.kind {
            case .chrome:
                urls = try SQLiteReader.strings(
                    dbPath: copy,
                    sql: "SELECT u.url FROM visits v JOIN urls u ON u.id = v.url WHERE v.visit_time > ?",
                    bind: Int64((since + 11_644_473_600) * 1_000_000))
            case .firefox:
                urls = try SQLiteReader.strings(
                    dbPath: copy,
                    sql: "SELECT p.url FROM moz_historyvisits v JOIN moz_places p ON p.id = v.place_id WHERE v.visit_date > ?",
                    bind: Int64(since * 1_000_000))
            }
            for raw in urls {
                guard let url = URL(string: raw), let host = normalizedHost(url) else { continue }
                index.hosts[host, default: [:]][source.target, default: 0] += 1
                if let id = GoogleDecoder.fileID(in: url) {
                    index.fileIDs[id, default: []].insert(source.target)
                }
            }
        }
        return index
    }
}

public enum AccessCheck {
    public static func canRead(_ path: URL) -> Bool {
        FileManager.default.isReadableFile(atPath: path.path) && (try? FileHandle(forReadingFrom: path).close()) != nil
    }
}
