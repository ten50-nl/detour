import Foundation

public enum GoogleDecoder {
    private static let fileHosts: Set<String> = ["docs.google.com", "drive.google.com", "sheets.google.com", "slides.google.com"]

    public static func accountEmail(in url: URL) -> String? {
        guard let host = normalizedHost(url),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        let isCalendar = host == "calendar.google.com" || (host == "google.com" && url.path.hasPrefix("/calendar"))
        if isCalendar, let eid = items.first(where: { $0.name == "eid" })?.value, let email = decodeEid(eid) {
            return email
        }
        if host.hasSuffix("google.com"), let user = items.first(where: { $0.name == "authuser" })?.value, isEmail(user) {
            return user.lowercased()
        }
        return nil
    }

    public static func fileID(in url: URL) -> String? {
        guard let host = normalizedHost(url), fileHosts.contains(host) else { return nil }
        let parts = url.pathComponents
        if let i = parts.firstIndex(of: "d"), i + 1 < parts.count, parts[i + 1].count >= 20 {
            return parts[i + 1]
        }
        if let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value,
           id.count >= 20 {
            return id
        }
        return nil
    }

    static func decodeEid(_ eid: String) -> String? {
        var b64 = eid.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let text = String(data: data, encoding: .utf8),
              let space = text.firstIndex(of: " ") else { return nil }
        var email = text[text.index(after: space)...].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if email.hasSuffix("@m") { email = String(email.dropLast(2)) + "@gmail.com" }
        return isEmail(email) ? email : nil
    }

    static func isEmail(_ s: String) -> Bool {
        guard let at = s.firstIndex(of: "@"), at != s.startIndex else { return false }
        return s[s.index(after: at)...].contains(".")
    }
}
