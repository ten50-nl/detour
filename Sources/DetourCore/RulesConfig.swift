import Foundation

public struct SourceRule: Codable, Equatable, Sendable {
    public var app: String
    public var titleContains: String?
    public var target: DestinationID

    public init(app: String, titleContains: String? = nil, target: DestinationID) {
        self.app = app
        self.titleContains = titleContains
        self.target = target
    }
}

public struct RulesConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 2
    public static let maxDestinations = 9

    public var version: Int
    public var destinations: [Destination]
    public var defaultDestination: DestinationID
    public var accountMap: [String: DestinationID]
    public var sourceRules: [SourceRule]
    public var askHosts: [String]

    public init(version: Int = RulesConfig.currentVersion, destinations: [Destination], defaultDestination: DestinationID,
                accountMap: [String: DestinationID] = [:], sourceRules: [SourceRule] = [], askHosts: [String] = RulesConfig.defaultAskHosts) {
        self.version = version
        self.destinations = destinations
        self.defaultDestination = defaultDestination
        self.accountMap = accountMap
        self.sourceRules = sourceRules
        self.askHosts = askHosts
    }

    public func destination(_ id: DestinationID) -> Destination? {
        destinations.first { $0.id == id }
    }

    public func pruned() -> RulesConfig {
        var copy = self
        let ids = Set(destinations.map(\.id))
        copy.accountMap = accountMap.filter { ids.contains($0.value) }
        copy.sourceRules = sourceRules.filter { ids.contains($0.target) }
        if !ids.contains(defaultDestination) { copy.defaultDestination = destinations.first?.id ?? "" }
        return copy
    }

    public func displayNames() -> [DestinationID: String] {
        var counts: [String: Int] = [:]
        for dest in destinations { counts[dest.name, default: 0] += 1 }
        var out: [DestinationID: String] = [:]
        for dest in destinations {
            guard counts[dest.name, default: 0] > 1 else { out[dest.id] = dest.name; continue }
            let app = URL(fileURLWithPath: dest.appPath).deletingPathExtension().lastPathComponent
            out[dest.id] = dest.profileDir.map { "\(dest.name) (\(app), \($0))" } ?? "\(dest.name) (\(app))"
        }
        return out
    }

    public static let defaultAskHosts = ["docs.google.com", "drive.google.com", "mail.google.com", "calendar.google.com", "meet.google.com"]

    public static let empty = RulesConfig(destinations: [], defaultDestination: "")
}
