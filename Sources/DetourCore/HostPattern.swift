import Foundation

public func normalizedHost(_ url: URL) -> String? {
    guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
    while host.hasSuffix(".") { host.removeLast() }
    if host.hasPrefix("www.") { host.removeFirst(4) }
    return host.isEmpty ? nil : host
}

public struct HostPattern: Sendable {
    private enum Kind: Sendable {
        case keyword(String)
        case domain(String)
        case hostRegex(NSRegularExpression)
        case urlRegex(NSRegularExpression)
    }

    public let raw: String
    private let kind: Kind

    public init(_ raw: String) {
        self.raw = raw
        let pattern = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if pattern.hasPrefix("~") {
            kind = .keyword(String(pattern.dropFirst()))
        } else if pattern.hasPrefix("url:") {
            let glob = String(pattern.dropFirst(4))
            let body = glob.split(separator: "*", omittingEmptySubsequences: false)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: ".*")
            kind = .urlRegex(Self.regex("^" + body + "$"))
        } else if pattern.contains("*") {
            var rest = Substring(pattern)
            var prefix = ""
            if rest.hasPrefix("*.") {
                prefix = "(?:.+\\.)?"
                rest = rest.dropFirst(2)
            }
            let body = rest.split(separator: "*", omittingEmptySubsequences: false)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "[^.]*")
            kind = .hostRegex(Self.regex("^" + prefix + body + "$"))
        } else {
            kind = .domain(pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern)
        }
    }

    public func matches(_ url: URL) -> Bool {
        switch kind {
        case .urlRegex(let re):
            return Self.fullMatch(re, url.absoluteString.lowercased())
        case .keyword(let keyword):
            guard let host = normalizedHost(url) else { return false }
            return host.contains(keyword)
        case .domain(let domain):
            guard let host = normalizedHost(url) else { return false }
            return host == domain || host.hasSuffix("." + domain)
        case .hostRegex(let re):
            guard let host = normalizedHost(url) else { return false }
            return Self.fullMatch(re, host)
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        (try? NSRegularExpression(pattern: pattern)) ?? NSRegularExpression()
    }

    private static func fullMatch(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}
