import Foundation

public enum SourceStrength: String, Codable, Sendable, CaseIterable {
    case always, whenUnsure, tieBreaker
}

public struct SourceRule: Codable, Equatable, Hashable, Sendable {
    public var app: String
    public var titleContains: String?
    public var target: DestinationID
    public var strength: SourceStrength

    public init(app: String, titleContains: String? = nil, target: DestinationID, strength: SourceStrength = .whenUnsure) {
        self.app = app
        self.titleContains = titleContains
        self.target = target
        self.strength = strength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decode(String.self, forKey: .app)
        titleContains = try c.decodeIfPresent(String.self, forKey: .titleContains)
        target = try c.decode(DestinationID.self, forKey: .target)
        strength = try c.decodeIfPresent(SourceStrength.self, forKey: .strength) ?? .tieBreaker
    }

    public func matches(app other: String, title: String?) -> Bool {
        guard app.caseInsensitiveCompare(other) == .orderedSame else { return false }
        guard let needle = titleContains?.lowercased(), !needle.isEmpty else { return true }
        return (title ?? "").lowercased().contains(needle)
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
    public var openInApps: Bool
    public var cleanLinks: Bool

    public init(version: Int = RulesConfig.currentVersion, destinations: [Destination], defaultDestination: DestinationID,
                accountMap: [String: DestinationID] = [:], sourceRules: [SourceRule] = [], askHosts: [String] = RulesConfig.defaultAskHosts,
                openInApps: Bool = false, cleanLinks: Bool = true) {
        self.version = version
        self.destinations = destinations
        self.defaultDestination = defaultDestination
        self.accountMap = accountMap
        self.sourceRules = sourceRules
        self.askHosts = askHosts
        self.openInApps = openInApps
        self.cleanLinks = cleanLinks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? RulesConfig.currentVersion
        destinations = try c.decode([Destination].self, forKey: .destinations)
        defaultDestination = try c.decode(DestinationID.self, forKey: .defaultDestination)
        accountMap = try c.decodeIfPresent([String: DestinationID].self, forKey: .accountMap) ?? [:]
        sourceRules = try c.decodeIfPresent([SourceRule].self, forKey: .sourceRules) ?? []
        askHosts = try c.decodeIfPresent([String].self, forKey: .askHosts) ?? RulesConfig.defaultAskHosts
        openInApps = try c.decodeIfPresent(Bool.self, forKey: .openInApps) ?? false
        cleanLinks = try c.decodeIfPresent(Bool.self, forKey: .cleanLinks) ?? true
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
