import AppKit
import DetourCore

@MainActor
enum BrowserScanner {
    static func installedBrowsers() -> [BrowserApp] {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
        var seen = Set<String>()
        var apps: [BrowserApp] = []
        for url in urls {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id),
                  id != BrowserDiscovery.ownBundleID, !excluded.contains(id) else { continue }
            seen.insert(id)
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            apps.append(BrowserApp(bundleID: id, name: name, appPath: url.path))
        }
        return apps.sorted { rank($0) < rank($1) }
    }

    static func profiles(for app: BrowserApp) -> [ProfileInfo]? {
        guard let url = Paths.localState(for: app.bundleID), let data = try? Data(contentsOf: url) else { return nil }
        let found = ChromeProfiles.profiles(localStateData: data)
        return found.isEmpty ? nil : found
    }

    static let isDemo = ProcessInfo.processInfo.environment["DETOUR_DEMO"] != nil

    static func candidates() -> [Destination] {
        if isDemo { return demoCandidates() }
        return BrowserDiscovery.candidates(apps: installedBrowsers(), profiles: profiles(for:))
    }

    private static func demoCandidates() -> [Destination] {
        let chrome = BrowserApp(bundleID: "com.google.Chrome", name: "Google Chrome", appPath: "/Applications/Google Chrome.app")
        let apps = [chrome,
                    BrowserApp(bundleID: "org.mozilla.firefox", name: "Firefox", appPath: "/Applications/Firefox.app"),
                    BrowserApp(bundleID: "com.apple.Safari", name: "Safari", appPath: "/Applications/Safari.app")]
        var found = BrowserDiscovery.candidates(apps: apps) { app in
            app.bundleID == chrome.bundleID
                ? [ProfileInfo(dir: "Default", name: "Personal", email: "sam@example.com"),
                   ProfileInfo(dir: "Profile 1", name: "Work", email: "sam@acme.com"),
                   ProfileInfo(dir: "Profile 2", name: "Side project", email: nil)]
                : nil
        }
        if let i = found.firstIndex(where: { $0.bundleID == "org.mozilla.firefox" }) { found[i].name = "Ad-free" }
        return found
    }

    static func demoSuggestions(destinations: [Destination], defaultID: DestinationID) -> [DestinationID: [RuleSuggestion]] {
        guard let work = destinations.first(where: { $0.account == "sam@acme.com" }) else { return [:] }
        let hosts = [("acme.atlassian.net", 412), ("app.hubspot.com", 188), ("acme.slack.com", 141), ("figma.com", 96), ("vercel.com", 53)]
        return [work.id: hosts.map { RuleSuggestion(host: $0.0, destination: work.id, visits: $0.1, share: 0.97) }]
    }

    static func icon(for destination: Destination) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: destination.appPath)
        image.size = NSSize(width: 32, height: 32)
        return image
    }

    private static let excluded: Set<String> = ["com.choosyosx.choosy", "nl.ten50.linkrouter", "com.sindresorhus.Velja", "se.johnste.finicky", "com.apple.Notes"]

    private static func rank(_ app: BrowserApp) -> Int {
        let order = ["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "company.thebrowser.Browser",
                     "org.mozilla.firefox", "com.apple.Safari"]
        return order.firstIndex(of: app.bundleID) ?? order.count
    }
}
