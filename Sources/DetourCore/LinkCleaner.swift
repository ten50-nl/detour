import Foundation

public enum LinkCleaner {
    static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid", "li_fat_id",
        "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id",
    ]
    static let shareParamHosts: Set<String> = ["youtube.com", "m.youtube.com", "youtu.be", "music.youtube.com", "open.spotify.com"]

    public static func clean(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems, !items.isEmpty else { return url }
        let host = normalizedHost(url) ?? ""
        let kept = items.filter { item in
            let name = item.name.lowercased()
            if name.hasPrefix("utm_") || trackingParams.contains(name) { return false }
            if name == "si" && shareParamHosts.contains(host) { return false }
            return true
        }
        guard kept.count != items.count else { return url }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}

public struct AppLink: Equatable, Sendable {
    public var app: String
    public var url: URL
}

public enum AppLinks {
    public static func convert(_ url: URL) -> AppLink? {
        guard let host = normalizedHost(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if host == "zoom.us" || host.hasSuffix(".zoom.us"), parts.count >= 2, parts[0] == "j", parts[1].allSatisfy(\.isNumber) {
            var c = URLComponents()
            c.scheme = "zoommtg"
            c.host = "zoom.us"
            c.path = "/join"
            c.queryItems = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[1])]
                + (query.first { $0.name == "pwd" }.map { [URLQueryItem(name: "pwd", value: $0.value)] } ?? [])
            return c.url.map { AppLink(app: "Zoom", url: $0) }
        }

        if host == "teams.microsoft.com" || host == "teams.live.com", parts.first == "l" {
            let path = url.path(percentEncoded: true)
            let q = url.query(percentEncoded: true).map { "?\($0)" } ?? ""
            return URL(string: "msteams:\(path)\(q)").map { AppLink(app: "Microsoft Teams", url: $0) }
        }

        if host == "app.slack.com", parts.count >= 3, parts[0] == "client" {
            return URL(string: "slack://channel?team=\(parts[1])&id=\(parts[2])").map { AppLink(app: "Slack", url: $0) }
        }

        let spotifyTypes: Set<String> = ["track", "album", "playlist", "artist", "episode", "show"]
        if host == "open.spotify.com", parts.count >= 2 {
            let offset = parts[0].hasPrefix("intl-") ? 1 : 0
            if parts.count >= offset + 2, spotifyTypes.contains(parts[offset]) {
                return URL(string: "spotify:\(parts[offset]):\(parts[offset + 1])").map { AppLink(app: "Spotify", url: $0) }
            }
        }

        if host == "music.apple.com", parts.count >= 2 {
            return URL(string: "music://music.apple.com\(url.path(percentEncoded: true))").map { AppLink(app: "Music", url: $0) }
        }

        if host == "discord.com", parts.count >= 3, parts[0] == "channels" {
            return URL(string: "discord://-\(url.path(percentEncoded: true))").map { AppLink(app: "Discord", url: $0) }
        }
        if host == "discord.gg", parts.count == 1 {
            return URL(string: "discord://-/invite/\(parts[0])").map { AppLink(app: "Discord", url: $0) }
        }

        if host == "linear.app", parts.count >= 3, ["issue", "project", "view", "team"].contains(parts[1]) {
            return URL(string: "linear:/\(url.path(percentEncoded: true))").map { AppLink(app: "Linear", url: $0) }
        }

        if host == "notion.so", parts.count >= 1, !["login", "signup", "product", "pricing", "help"].contains(parts[0]) {
            return URL(string: "notion://www.notion.so\(url.path(percentEncoded: true))").map { AppLink(app: "Notion", url: $0) }
        }
        return nil
    }
}

public enum LaunchArguments {
    static let firefoxFamily: Set<String> = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly", "app.zen-browser.zen", "net.waterfox.waterfox"]

    public static func supportsPrivate(_ dest: Destination) -> Bool {
        ChromiumFamily.supportDirs[dest.bundleID] != nil || firefoxFamily.contains(dest.bundleID)
    }

    public static func arguments(for dest: Destination, url: URL) -> [String]? {
        var args: [String] = []
        if ChromiumFamily.supportDirs[dest.bundleID] != nil {
            if let dir = dest.profileDir { args.append("--profile-directory=\(dir)") }
            if dest.privateWindow { args.append("--incognito") }
        } else if firefoxFamily.contains(dest.bundleID), dest.privateWindow {
            args.append("-private-window")
        }
        guard !args.isEmpty else { return nil }
        return args + [url.absoluteString]
    }
}
