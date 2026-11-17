import Foundation
import Testing
@testable import DetourCore

@Suite struct DestinationMergeTests {
    let saved = [
        Destination(id: "work", name: "Work", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", profileDir: "Profile 3", color: "#111111", patterns: ["~acme"]),
        Destination(id: "firefox", name: "Ad-free", appPath: "/Applications/Firefox.app", bundleID: "org.mozilla.firefox", patterns: ["youtube.com"]),
        Destination(id: "personal", name: "Personal", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", profileDir: "Default", patterns: ["linkedin.com"]),
    ]
    let scanned = [
        Destination(id: "google-chrome-default", name: "Me", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", profileDir: "Default"),
        Destination(id: "google-chrome-profile-3", name: "Acme", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", profileDir: "Profile 3"),
        Destination(id: "firefox", name: "Firefox", appPath: "/Applications/Firefox.app", bundleID: "org.mozilla.firefox"),
        Destination(id: "safari", name: "Safari", appPath: "/Applications/Safari.app", bundleID: "com.apple.Safari"),
    ]

    @Test func savedDestinationsKeepIdNamePatternsAndOrder() {
        let merged = DestinationMerge.merge(saved: saved, scanned: scanned)
        #expect(merged.map { $0.id } == ["work", "firefox", "personal", "safari"])
        #expect(merged[0].name == "Work")
        #expect(merged[0].patterns == ["~acme"])
        #expect(merged[0].color == "#111111")
        #expect(merged[2].patterns == ["linkedin.com"])
    }

    @Test func savedButNotScannedIsKept() {
        let merged = DestinationMerge.merge(saved: saved, scanned: [])
        #expect(merged.map { $0.id } == ["work", "firefox", "personal"])
    }

    @Test func wholeBrowserBecomesProfileKeepsSavedEntry() {
        let wholeChrome = [Destination(id: "google-chrome", name: "Google Chrome", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome")]
        let merged = DestinationMerge.merge(saved: wholeChrome, scanned: scanned)
        #expect(merged.first?.id == "google-chrome")
        #expect(merged.contains { $0.id == "google-chrome-default" })
    }

    @Test func newScannedIdsNeverCollideWithSaved() {
        let clash = [Destination(id: "safari", name: "Old", appPath: "/Applications/Other.app", bundleID: "com.other")]
        let merged = DestinationMerge.merge(saved: clash, scanned: scanned)
        #expect(Set(merged.map(\.id)).count == merged.count)
    }

    @Test func duplicateSavedIdsDoNotCrash() {
        let dupes = [saved[0], saved[0]]
        let merged = DestinationMerge.merge(saved: dupes, scanned: [])
        #expect(merged.count == 1)
    }
}
