import Foundation

public enum ConfigLoader {
    public static func loadRules(from url: URL, fallback: RulesConfig) -> (RulesConfig, Error?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (fallback, nil) }
        do {
            let data = try Data(contentsOf: url)
            do {
                return (try JSONDecoder().decode(RulesConfig.self, from: data), nil)
            } catch {
                guard let migrated = try? LegacyImport.rules(fromV1: data) else { throw error }
                return (migrated, nil)
            }
        } catch {
            return (fallback, error)
        }
    }

    public enum ImportError: LocalizedError, Equatable {
        case notDetourSettings, noDestinations
        public var errorDescription: String? {
            switch self {
            case .notDetourSettings: "This file doesn't contain Detour settings."
            case .noDestinations: "This file has no destinations, so nothing was imported."
            }
        }
    }

    public static func importRules(from data: Data) throws -> RulesConfig {
        let imported: RulesConfig
        if let config = try? JSONDecoder().decode(RulesConfig.self, from: data) {
            imported = config
        } else if let legacy = try? LegacyImport.rules(fromV1: data) {
            imported = legacy
        } else {
            throw ImportError.notDetourSettings
        }
        guard !imported.destinations.isEmpty else { throw ImportError.noDestinations }
        return imported
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
