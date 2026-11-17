import Foundation

public enum HostVerdict: Equatable, Sendable {
    case none
    case confident(DestinationID, share: Double, total: Int)
    case mixed(counts: [DestinationID: Int])
}

public struct HistoryIndex: Codable, Equatable, Sendable {
    public static let minVisits = 5
    public static let minShare = 0.8

    public var hosts: [String: [DestinationID: Int]]
    public var paths: [String: [DestinationID: Int]]
    public var fileIDs: [String: Set<DestinationID>]
    public var builtAt: Date

    public init(hosts: [String: [DestinationID: Int]] = [:], paths: [String: [DestinationID: Int]] = [:],
                fileIDs: [String: Set<DestinationID>] = [:], builtAt: Date = Date()) {
        self.hosts = hosts
        self.paths = paths
        self.fileIDs = fileIDs
        self.builtAt = builtAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try c.decode([String: [DestinationID: Int]].self, forKey: .hosts)
        paths = try c.decodeIfPresent([String: [DestinationID: Int]].self, forKey: .paths) ?? [:]
        fileIDs = try c.decode([String: Set<DestinationID>].self, forKey: .fileIDs)
        builtAt = try c.decode(Date.self, forKey: .builtAt)
    }

    public func hostVerdict(_ host: String) -> HostVerdict {
        Self.verdict(hosts[host])
    }

    public func pathVerdict(_ key: String) -> HostVerdict {
        Self.verdict(paths[key])
    }

    static func verdict(_ counts: [DestinationID: Int]?) -> HostVerdict {
        guard let counts, !counts.isEmpty else { return .none }
        let total = counts.values.reduce(0, +)
        if let top = counts.max(by: { $0.value < $1.value }), total >= minVisits {
            let share = Double(top.value) / Double(total)
            if share >= minShare { return .confident(top.key, share: share, total: total) }
        }
        return .mixed(counts: counts)
    }

    public func fileTarget(_ id: String) -> DestinationID? {
        guard let set = fileIDs[id], set.count == 1 else { return nil }
        return set.first
    }
}
