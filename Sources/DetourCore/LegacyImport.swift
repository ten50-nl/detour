import Foundation

public enum LegacyImport {
    struct ImportError: Error {}

    private struct V1Target: Decodable {
        var id: String
        var label: String
        var appPath: String
        var chromeProfileDir: String?
        var expectedProfileName: String?
    }

    private struct V1Common: Decodable {
        var targets: [V1Target]
        var accountMap: [String: String]
        var sourceRules: [SourceRule]
        var ambiguousHosts: [String]
    }

    public static func rules(fromV1 data: Data) throws -> RulesConfig {
        let common = try JSONDecoder().decode(V1Common.self, from: data)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], !common.targets.isEmpty else { throw ImportError() }
        let fallback = common.targets.first { $0.id == "personal" } ?? common.targets.last!
        let ordered = common.targets.filter { $0.id != fallback.id } + [fallback]
        let destinations = ordered.enumerated().map { index, target in
            Destination(
                id: target.id,
                name: target.label,
                appPath: target.appPath,
                bundleID: Bundle(path: target.appPath)?.bundleIdentifier ?? guessBundleID(target.appPath),
                profileDir: target.chromeProfileDir,
                profileName: target.expectedProfileName,
                color: BrowserDiscovery.palette[index % BrowserDiscovery.palette.count],
                patterns: root[target.id] as? [String] ?? [])
        }
        return RulesConfig(destinations: destinations, defaultDestination: fallback.id, accountMap: common.accountMap,
                           sourceRules: common.sourceRules, askHosts: common.ambiguousHosts)
    }

    public static func learned(fromV1 data: Data) throws -> LearnedStore {
        try JSONDecoder().decode(LearnedStore.self, from: data)
    }

    private static func guessBundleID(_ appPath: String) -> String {
        switch URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent {
        case "Google Chrome": "com.google.Chrome"
        case "Firefox": "org.mozilla.firefox"
        case "Safari": "com.apple.Safari"
        default: ""
        }
    }
}
