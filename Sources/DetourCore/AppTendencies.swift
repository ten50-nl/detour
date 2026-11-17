import Foundation

public struct AppTendencies: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var app: String
        public var target: DestinationID
        public var stage: Stage

        public init(app: String, target: DestinationID, stage: Stage) {
            self.app = app
            self.target = target
            self.stage = stage
        }
    }

    public struct Tendency: Sendable, Equatable {
        public var target: DestinationID
        public var share: Double
        public var total: Int
    }

    public static let minLinks = 10
    public static let minShare = 0.85
    static let countedStages: Set<Stage> = [.rule, .decoder, .learned, .history, .ambiguous, .forced]
    static let ignoredApps: Set<String> = ["detour"]

    public private(set) var counts: [String: [DestinationID: Int]] = [:]
    private var names: [String: String] = [:]

    public init(entries: [Entry] = []) {
        for entry in entries { add(entry) }
    }

    public mutating func add(_ entry: Entry) {
        let key = entry.app.lowercased()
        guard !entry.target.isEmpty, !Self.ignoredApps.contains(key), Self.countedStages.contains(entry.stage) else { return }
        counts[key, default: [:]][entry.target, default: 0] += 1
        if names[key] == nil { names[key] = entry.app }
    }

    public func target(for app: String) -> Tendency? {
        guard let byTarget = counts[app.lowercased()] else { return nil }
        let total = byTarget.values.reduce(0, +)
        guard total >= Self.minLinks, let top = byTarget.max(by: { $0.value < $1.value }) else { return nil }
        let share = Double(top.value) / Double(total)
        return share >= Self.minShare ? Tendency(target: top.key, share: share, total: total) : nil
    }

    public var all: [(app: String, tendency: Tendency)] {
        counts.keys.sorted().compactMap { key in target(for: key).map { (names[key] ?? key, $0) } }
    }
}
