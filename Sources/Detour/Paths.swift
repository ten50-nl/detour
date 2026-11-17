import DetourCore
import Foundation

enum Paths {
    static let home: URL = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir)) }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    static let ownLibrary = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first ?? home.appendingPathComponent("Library")
    static let overrideDir = ProcessInfo.processInfo.environment["DETOUR_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
    static var isIsolated: Bool { overrideDir != nil }
    static let support = overrideDir ?? ownLibrary.appendingPathComponent("Application Support/Detour")
    static let rules = support.appendingPathComponent("rules.json")
    static let learned = support.appendingPathComponent("learned.json")
    static let historyIndex = support.appendingPathComponent("history-index.json")
    static let decisions = support.appendingPathComponent("decisions.jsonl")
    static let cache = overrideDir.map { $0.appendingPathComponent("cache") } ?? ownLibrary.appendingPathComponent("Caches/Detour")
    static let appSupport = home.appendingPathComponent("Library/Application Support")
    static let firefoxRoot = appSupport.appendingPathComponent("Firefox")
    static let legacySupport = appSupport.appendingPathComponent("LinkRouter")
    static let legacyRules = legacySupport.appendingPathComponent("rules.json")
    static let legacyLearned = legacySupport.appendingPathComponent("learned.json")
    static var fullDiskAccessProbes: [URL] {
        ChromiumFamily.supportDirs.values.map { appSupport.appendingPathComponent($0).appendingPathComponent("Local State") }
            + [home.appendingPathComponent("Library/Safari/Bookmarks.plist"),
               home.appendingPathComponent("Library/Safari/History.db"),
               firefoxRoot.appendingPathComponent("profiles.ini"),
               appSupport.appendingPathComponent("com.apple.TCC/TCC.db")]
    }

    static var isAppStore: Bool {
        #if MAS
        true
        #else
        false
        #endif
    }

    static func localState(for bundleID: String) -> URL? {
        ChromiumFamilyPaths.supportDir(bundleID).map { $0.appendingPathComponent("Local State") }
    }
}

enum ChromiumFamilyPaths {
    static func supportDir(_ bundleID: String) -> URL? {
        guard let dir = ChromiumFamily.supportDirs[bundleID] else { return nil }
        return Paths.appSupport.appendingPathComponent(dir)
    }
}
