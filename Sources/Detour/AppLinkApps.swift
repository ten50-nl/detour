import AppKit

enum AppLinkApps {
    static let bundles: [String: [String]] = [
        "Zoom": ["us.zoom.xos"],
        "Microsoft Teams": ["com.microsoft.teams2", "com.microsoft.teams"],
        "Slack": ["com.tinyspeck.slackmacgap"],
    ]

    static func installed() -> Set<String> {
        Set(bundles.compactMap { app, ids in
            ids.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil } ? app : nil
        })
    }

    static func availability() -> @Sendable (String) -> Bool {
        let apps = installed()
        return { apps.contains($0) }
    }
}
