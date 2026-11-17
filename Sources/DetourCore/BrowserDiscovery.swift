import Foundation

public struct BrowserApp: Equatable, Sendable {
    public var bundleID: String
    public var name: String
    public var appPath: String

    public init(bundleID: String, name: String, appPath: String) {
        self.bundleID = bundleID
        self.name = name
        self.appPath = appPath
    }
}

public struct ProfileInfo: Equatable, Sendable {
    public var dir: String
    public var name: String
    public var email: String?

    public init(dir: String, name: String, email: String?) {
        self.dir = dir
        self.name = name
        self.email = email
    }
}

public enum ChromiumFamily {
    public static let supportDirs: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "org.chromium.Chromium": "Chromium",
    ]

    public static func supportDir(for bundleID: String, appSupport: URL) -> URL? {
        supportDirs[bundleID].map { appSupport.appendingPathComponent($0) }
    }
}

public enum BrowserDiscovery {
    public static let ownBundleID = "nl.ten50.detour"
    public static let palette = ["#4F8BFF", "#34C759", "#FF7A1A", "#AF52DE", "#FF375F", "#00C7BE", "#FFCC00", "#5E5CE6", "#A2845E"]

    public static func candidates(apps: [BrowserApp], profiles: (BrowserApp) -> [ProfileInfo]?) -> [Destination] {
        var out: [Destination] = []
        for app in apps where app.bundleID != ownBundleID {
            let appSlug = slug(app.name)
            if ChromiumFamily.supportDirs[app.bundleID] != nil, let found = profiles(app), !found.isEmpty {
                for profile in found {
                    out.append(Destination(id: "\(appSlug)-\(slug(profile.dir))", name: profile.name, appPath: app.appPath,
                                           bundleID: app.bundleID, profileDir: profile.dir, profileName: profile.name,
                                           account: profile.email))
                }
            } else {
                out.append(Destination(id: appSlug, name: app.name, appPath: app.appPath, bundleID: app.bundleID))
            }
        }
        for i in out.indices { out[i].color = palette[i % palette.count] }
        return out
    }

    public static func slug(_ text: String) -> String {
        let lowered = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(lowered).split(separator: "-").joined(separator: "-")
    }
}
