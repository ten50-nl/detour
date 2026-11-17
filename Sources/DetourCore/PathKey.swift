import Foundation

public enum PathKey {
    static let workspaceHosts: Set<String> = ["github.com", "gitlab.com", "bitbucket.org", "notion.so", "linear.app", "vercel.com"]
    static let reserved: Set<String> = [
        "settings", "login", "logout", "signup", "sign_up", "join", "explore", "marketplace", "notifications", "new",
        "search", "pricing", "features", "about", "topics", "trending", "sponsors", "dashboard", "account", "api",
        "orgs", "organizations", "users", "help", "docs", "blog", "security", "enterprise", "team", "teams", "-",
        "pulls", "issues", "codespaces", "copilot", "apps", "login-redirect", "auth", "oauth", "invite",
    ]

    public static func key(for url: URL) -> String? {
        guard let host = normalizedHost(url) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        if workspaceHosts.contains(host) {
            guard let first = parts.first, !first.isEmpty, !reserved.contains(first), !first.hasPrefix(".") else { return nil }
            return "\(host)/\(first)"
        }
        if host == "figma.com", parts.count >= 3, parts[0] == "files", parts[1] == "team" {
            return "\(host)/files/team/\(parts[2])"
        }
        return nil
    }
}
