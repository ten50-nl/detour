import Foundation

public struct LearnedStore: Codable, Equatable, Sendable {
    public var hosts: [String: DestinationID]
    public var fileIDs: [String: DestinationID]

    public init(hosts: [String: DestinationID] = [:], fileIDs: [String: DestinationID] = [:]) {
        self.hosts = hosts
        self.fileIDs = fileIDs
    }

    public mutating func remember(url: URL, target: DestinationID) {
        if let id = GoogleDecoder.fileID(in: url) {
            fileIDs[id] = target
        } else if let host = normalizedHost(url) {
            hosts[host] = target
        }
    }

    public func pruned(validIDs: Set<DestinationID>) -> LearnedStore {
        LearnedStore(hosts: hosts.filter { validIDs.contains($0.value) }, fileIDs: fileIDs.filter { validIDs.contains($0.value) })
    }

    public func lookup(url: URL) -> (DestinationID, String)? {
        if let id = GoogleDecoder.fileID(in: url), let target = fileIDs[id] {
            return (target, "learned for this file")
        }
        if let host = normalizedHost(url), let target = hosts[host] {
            return (target, "learned for \(host)")
        }
        return nil
    }
}
