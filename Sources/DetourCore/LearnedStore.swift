import Foundation

public struct LearnedStore: Codable, Equatable, Sendable {
    public var hosts: [String: DestinationID]
    public var paths: [String: DestinationID]
    public var fileIDs: [String: DestinationID]

    public init(hosts: [String: DestinationID] = [:], paths: [String: DestinationID] = [:], fileIDs: [String: DestinationID] = [:]) {
        self.hosts = hosts
        self.paths = paths
        self.fileIDs = fileIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hosts = try c.decodeIfPresent([String: DestinationID].self, forKey: .hosts) ?? [:]
        paths = try c.decodeIfPresent([String: DestinationID].self, forKey: .paths) ?? [:]
        fileIDs = try c.decodeIfPresent([String: DestinationID].self, forKey: .fileIDs) ?? [:]
    }

    public mutating func remember(url: URL, target: DestinationID) {
        if let id = GoogleDecoder.fileID(in: url) {
            fileIDs[id] = target
        } else if let key = PathKey.key(for: url) {
            paths[key] = target
        } else if let host = normalizedHost(url) {
            hosts[host] = target
        }
    }

    public func pruned(validIDs: Set<DestinationID>) -> LearnedStore {
        LearnedStore(hosts: hosts.filter { validIDs.contains($0.value) },
                     paths: paths.filter { validIDs.contains($0.value) },
                     fileIDs: fileIDs.filter { validIDs.contains($0.value) })
    }

    public func lookup(url: URL) -> (DestinationID, String)? {
        if let id = GoogleDecoder.fileID(in: url), let target = fileIDs[id] {
            return (target, "learned for this file")
        }
        if let key = PathKey.key(for: url), let target = paths[key] {
            return (target, "learned for \(key)")
        }
        if let host = normalizedHost(url), let target = hosts[host] {
            return (target, "learned for \(host)")
        }
        return nil
    }
}
