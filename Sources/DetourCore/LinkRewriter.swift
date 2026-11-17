import Foundation

public struct RewriteRule: Codable, Equatable, Hashable, Sendable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    public static func make(from: String, to: String) -> RewriteRule? {
        guard let source = host(from), let target = host(to), source != target else { return nil }
        return RewriteRule(from: source, to: target)
    }

    static func host(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), let host = normalizedHost(url) else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard host.contains("."), host.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return host
    }

    func matches(_ host: String) -> Bool {
        host == from || host.hasSuffix("." + from)
    }
}

public enum LinkRewriter {
    public static func rewrite(_ url: URL, rules: [RewriteRule]) -> URL {
        guard !rules.isEmpty, let host = normalizedHost(url), let rule = rules.first(where: { $0.matches(host) }),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.host = rule.to
        return components.url ?? url
    }
}

extension RulesConfig {
    public func prepare(_ url: URL) -> URL {
        let rewritten = LinkRewriter.rewrite(url, rules: rewrites)
        return cleanLinks ? LinkCleaner.clean(rewritten) : rewritten
    }
}
