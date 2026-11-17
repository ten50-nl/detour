import Foundation

public enum DestinationMerge {
    public static func key(_ dest: Destination) -> String {
        "\(dest.bundleID)|\(dest.profileDir ?? "")\(dest.privateWindow ? "|private" : "")"
    }

    public static func merge(saved: [Destination], scanned: [Destination]) -> [Destination] {
        var out: [Destination] = []
        var keys = Set<String>()
        var ids = Set<DestinationID>()
        for dest in saved where !keys.contains(key(dest)) && !ids.contains(dest.id) {
            out.append(dest)
            keys.insert(key(dest))
            ids.insert(dest.id)
        }
        for var dest in scanned where !keys.contains(key(dest)) {
            let base = dest.id
            var n = 2
            while ids.contains(dest.id) {
                dest.id = "\(base)-\(n)"
                n += 1
            }
            out.append(dest)
            keys.insert(key(dest))
            ids.insert(dest.id)
        }
        return out
    }
}
