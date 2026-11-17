import Foundation

public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !trimmed.isEmpty, !pieces.isEmpty else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard let n = Int(piece), n >= 0 else { return nil }
            numbers.append(n)
        }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

public struct AvailableUpdate: Equatable, Sendable {
    public var version: String
    public var downloadURL: URL
    public var pageURL: URL?
    public var notes: String
}

public enum UpdateCheck {
    public static let interval: TimeInterval = 24 * 3600

    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var browser_download_url: String
        }
        var tag_name: String
        var html_url: String?
        var body: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]
    }

    public static func evaluate(currentVersion: String, releaseJSON: Data) -> AvailableUpdate? {
        guard let release = try? JSONDecoder().decode(Release.self, from: releaseJSON),
              release.draft != true, release.prerelease != true,
              let latest = AppVersion(release.tag_name), let current = AppVersion(currentVersion), latest > current else { return nil }
        let preferred = release.assets.first { $0.name == "Detour-\(latest).dmg" } ?? release.assets.first { $0.name == "Detour.dmg" }
        guard let asset = preferred, let url = URL(string: asset.browser_download_url), isTrustedDownload(url) else { return nil }
        return AvailableUpdate(version: latest.description, downloadURL: url, pageURL: release.html_url.flatMap(URL.init(string:)), notes: release.body ?? "")
    }

    public static func isTrustedDownload(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host() == "github.com" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.count >= 6 && parts[1] == "detour" && parts[2] == "releases" && parts[3] == "download" && parts.last?.hasSuffix(".dmg") == true
    }

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public static func teamIdentifier(fromCodesignOutput output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("TeamIdentifier=") {
            let value = String(line.dropFirst("TeamIdentifier=".count))
            return value == "not set" || value.isEmpty ? nil : value
        }
        return nil
    }
}
