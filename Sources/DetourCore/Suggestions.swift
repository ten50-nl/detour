import Foundation

public struct RuleSuggestion: Equatable, Identifiable, Sendable {
    public var id: String { host }
    public var host: String
    public var destination: DestinationID
    public var visits: Int
    public var share: Double

    public init(host: String, destination: DestinationID, visits: Int, share: Double) {
        self.host = host
        self.destination = destination
        self.visits = visits
        self.share = share
    }
}

public enum Suggestions {
    public static let publicMailDomains: Set<String> = [
        "gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "icloud.com", "me.com", "mac.com",
        "yahoo.com", "proton.me", "protonmail.com", "pm.me", "aol.com", "gmx.com", "gmx.net", "fastmail.com", "hey.com",
        "hotmail.nl", "hotmail.be", "hotmail.de", "hotmail.fr", "hotmail.co.uk", "live.nl", "live.be", "live.de", "live.co.uk",
        "outlook.nl", "outlook.be", "outlook.de", "outlook.fr", "yahoo.co.uk", "yahoo.de", "yahoo.fr", "yahoo.nl",
        "web.de", "gmx.de", "gmx.at", "gmx.ch", "t-online.de", "freenet.de", "orange.fr", "free.fr", "laposte.net",
        "ziggo.nl", "kpnmail.nl", "kpnplanet.nl", "planet.nl", "home.nl", "xs4all.nl", "telenet.be", "skynet.be",
        "btinternet.com", "sky.com", "virginmedia.com", "comcast.net", "verizon.net", "att.net", "tuta.com", "tutanota.com",
    ]

    public static let videoPreset = ["youtube.com", "youtu.be", "twitch.tv", "dailymotion.com", "vimeo.com"]

    public static func rules(index: HistoryIndex, destinations: [Destination], defaultID: DestinationID,
                             minShare: Double = 0.9, minVisits: Int = 20, perDestination: Int = 15) -> [DestinationID: [RuleSuggestion]] {
        let existing = destinations.flatMap(\.patterns).map(HostPattern.init)
        let ask = RulesConfig.defaultAskHosts.map(HostPattern.init)
        let valid = Set(destinations.map(\.id))
        var out: [DestinationID: [RuleSuggestion]] = [:]
        for (host, counts) in index.hosts {
            let total = counts.values.reduce(0, +)
            guard total >= minVisits, let top = counts.max(by: { $0.value < $1.value }), top.key != defaultID, valid.contains(top.key) else { continue }
            let share = Double(top.value) / Double(total)
            guard share >= minShare, top.value >= minVisits, let url = URL(string: "https://\(host)/") else { continue }
            if existing.contains(where: { $0.matches(url) }) || ask.contains(where: { $0.matches(url) }) { continue }
            out[top.key, default: []].append(RuleSuggestion(host: host, destination: top.key, visits: top.value, share: share))
        }
        for key in out.keys {
            out[key] = Array(out[key]!.sorted { ($0.visits, $1.host) > ($1.visits, $0.host) }.prefix(perDestination))
        }
        return out
    }

    public static let workChatApps = ["Slack", "Microsoft Teams", "Mattermost", "Discord", "Zoom", "Webex", "Google Chat", "Linear", "Jira"]
    public static let personalChatApps = ["Messages", "WhatsApp", "Telegram", "Signal", "Messenger", "FaceTime"]

    public static func workDestination(_ destinations: [Destination], defaultID: DestinationID) -> Destination? {
        destinations.first { dest in
            guard dest.id != defaultID, let email = dest.account?.lowercased(), let domain = email.split(separator: "@").last else { return false }
            return !publicMailDomains.contains(String(domain))
        }
    }

    public static func appRules(installedApps: [String], destinations: [Destination], defaultID: DestinationID, existing: [SourceRule]) -> [SourceRule] {
        let taken = Set(existing.map { $0.app.lowercased() })
        let installed = installedApps.filter { !taken.contains($0.lowercased()) }
        var out: [SourceRule] = []
        if let work = workDestination(destinations, defaultID: defaultID) {
            out += workChatApps.filter { app in installed.contains { $0.caseInsensitiveCompare(app) == .orderedSame } }
                .map { SourceRule(app: $0, target: work.id) }
        }
        if destinations.contains(where: { $0.id == defaultID }) {
            out += personalChatApps.filter { app in installed.contains { $0.caseInsensitiveCompare(app) == .orderedSame } }
                .map { SourceRule(app: $0, target: defaultID) }
        }
        return out
    }

    public static func accountMap(destinations: [Destination]) -> [String: DestinationID] {
        var byDomain: [String: Set<DestinationID>] = [:]
        var map: [String: DestinationID] = [:]
        for dest in destinations {
            guard let email = dest.account?.lowercased(), let domain = email.split(separator: "@").last.map(String.init) else { continue }
            map[email] = dest.id
            if !publicMailDomains.contains(domain) { byDomain[domain, default: []].insert(dest.id) }
        }
        for (domain, ids) in byDomain where ids.count == 1 {
            let id = ids.first!
            map = map.filter { !($0.key.hasSuffix("@" + domain) && $0.value == id) }
            map[domain] = id
        }
        return map
    }
}
