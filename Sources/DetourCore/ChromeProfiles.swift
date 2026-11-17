import Foundation

public enum ChromeProfiles {
    public static func profiles(localStateData: Data) -> [ProfileInfo] {
        guard let root = try? JSONSerialization.jsonObject(with: localStateData) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        let found = cache.compactMap { dir, value -> ProfileInfo? in
            guard let info = value as? [String: Any] else { return nil }
            let email = (info["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0.lowercased() }
            return ProfileInfo(dir: dir, name: (info["name"] as? String) ?? dir, email: email)
        }
        return found.sorted { sortKey($0.dir) < sortKey($1.dir) }
    }

    private static func sortKey(_ dir: String) -> (Int, Int, String) {
        if dir == "Default" { return (0, 0, dir) }
        if dir.hasPrefix("Profile "), let n = Int(dir.dropFirst(8)) { return (1, n, dir) }
        return (2, 0, dir)
    }

    public static func displayNames(localStateData: Data) -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: localStateData) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [:] }
        var names: [String: String] = [:]
        for (dir, value) in cache {
            if let info = value as? [String: Any], let name = info["name"] as? String {
                names[dir] = name
            }
        }
        return names
    }
}

public enum FirefoxProfiles {
    public static func defaultProfilePath(iniText: String, baseDir: URL) -> URL? {
        var sections: [[String: String]] = []
        for line in iniText.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("[") {
                sections.append(["_section": line])
            } else if let eq = line.firstIndex(of: "="), !sections.isEmpty {
                sections[sections.count - 1][String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        func resolve(_ path: String, relative: Bool) -> URL {
            relative ? baseDir.appendingPathComponent(path) : URL(fileURLWithPath: path)
        }
        if let install = sections.first(where: { $0["_section"]?.hasPrefix("[Install") == true }), let path = install["Default"] {
            return resolve(path, relative: !path.hasPrefix("/"))
        }
        let profiles = sections.filter { $0["_section"]?.hasPrefix("[Profile") == true }
        if let chosen = profiles.first(where: { $0["Default"] == "1" }) ?? profiles.first, let path = chosen["Path"] {
            return resolve(path, relative: chosen["IsRelative"] != "0")
        }
        return nil
    }
}

public struct ProfileProblem: Equatable, Sendable {
    public var message: String
    public var blocksRouting: Bool
}

public enum ProfileCheck {
    public static func problems(destinations: [Destination], names: [String: String]) -> [DestinationID: ProfileProblem] {
        var out: [DestinationID: ProfileProblem] = [:]
        for target in destinations {
            guard let dir = target.profileDir else { continue }
            let app = URL(fileURLWithPath: target.appPath).deletingPathExtension().lastPathComponent
            guard let actual = names[dir] else {
                out[target.id] = ProfileProblem(message: "\(app) has no profile folder \"\(dir)\" any more. Its links open in your default destination until you fix it in Detour settings.", blocksRouting: true)
                continue
            }
            if let expected = target.profileName, actual != expected {
                out[target.id] = ProfileProblem(message: "\(app) profile \"\(dir)\" is now called \"\(actual)\" instead of \"\(expected)\". Links still open there.", blocksRouting: false)
            }
        }
        return out
    }
}
