import Foundation
import DetourCore
import UserNotifications

@MainActor
enum Notifier {
    private static let fdaWorkedKey = "fullDiskAccessWorked"
    private static let fdaLostNotifiedKey = "fullDiskAccessLostNotified"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func fullDiskAccessWorks() {
        UserDefaults.standard.set(true, forKey: fdaWorkedKey)
        UserDefaults.standard.set(false, forKey: fdaLostNotifiedKey)
    }

    static func fullDiskAccessLost() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: fdaWorkedKey), !defaults.bool(forKey: fdaLostNotifiedKey) else { return }
        defaults.set(true, forKey: fdaLostNotifiedKey)
        post(title: "Detour lost Full Disk Access", body: "Links still follow your rules, but browser history is no longer used. Turn access back on in System Settings.")
    }

    static func profileMismatch(name: String, detail: String) {
        post(title: "Browser profile for \(name) changed", body: detail)
    }

    static func updateAvailable(version: String, homebrew: Bool) {
        post(title: "Detour \(version) is available",
             body: homebrew ? "Update with brew upgrade --cask detour." : "Install it from the menu bar icon or in Detour settings.")
    }

    static func rulesBroken() {
        post(title: "Detour could not read rules.json", body: "A copy is saved next to it as rules.broken-….json. Fix the file or set up Detour again from the menu bar.")
    }

    static func openFailed(url: URL) {
        post(title: "Detour could not open a link", body: "\(url.absoluteString) is in the menu bar list. Copy it from there.")
    }

    private static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
