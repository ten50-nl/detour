import Foundation

enum InstalledApps {
    static func names() -> [String] {
        let fm = FileManager.default
        let dirs = ["/Applications", "/System/Applications", Paths.home.appendingPathComponent("Applications").path]
        var names = Set<String>()
        for dir in dirs {
            for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
                names.insert(String(item.dropLast(4)))
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
