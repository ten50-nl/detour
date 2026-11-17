import Foundation

public enum LinkParser {
    public static func parse(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, encodingInvalidCharacters: true)
    }
}

public func openChain(_ id: DestinationID, default fallback: DestinationID) -> [DestinationID] {
    id == fallback || fallback.isEmpty ? [id] : [id, fallback]
}

public struct FileChangeDetector: Sendable {
    public let url: URL
    private var stamp: [String]

    public init(url: URL) {
        self.url = url
        stamp = Self.currentStamp(url)
    }

    public mutating func hasChanged() -> Bool {
        let now = Self.currentStamp(url)
        defer { stamp = now }
        return now != stamp
    }

    private static func currentStamp(_ url: URL) -> [String] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return [] }
        let date = (attrs[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
        return ["\(date)", "\(attrs[.size] ?? 0)", "\(attrs[.systemFileNumber] ?? 0)"]
    }
}
