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
    public var fileIDs: [String: Set<DestinationID>]
    public var builtAt: Date

    public init(hosts: [String: [DestinationID: Int]] = [:], fileIDs: [String: Set<DestinationID>] = [:], builtAt: Date = Date()) {
        self.hosts = hosts
        self.fileIDs = fileIDs
        self.builtAt = builtAt
    }

    public func hostVerdict(_ host: String) -> HostVerdict {
        guard let counts = hosts[host], !counts.isEmpty else { return .none }
        let total = counts.values.reduce(0, +)
        if let top = counts.max(by: { $0.value < $1.value }), total >= Self.minVisits {
            let share = Double(top.value) / Double(total)
            if share >= Self.minShare { return .confident(top.key, share: share, total: total) }
        }
        return .mixed(counts: counts)
    }

    public func fileTarget(_ id: String) -> DestinationID? {
        guard let set = fileIDs[id], set.count == 1 else { return nil }
        return set.first
    }
}
