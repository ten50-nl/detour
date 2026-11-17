import Foundation
import Testing
@testable import DetourCore

@Suite struct UpdateTests {
    @Test(arguments: [("1.2.0", "1.2.1", true), ("1.2.0", "1.10.0", true), ("1.2.0", "v2.0", true), ("1.2.0", "1.2.0", false),
                      ("1.2.0", "1.1.9", false), ("1.2", "1.2.0", false), ("1.2.0", "1.2.0.1", true)])
    func versionOrder(current: String, latest: String, newer: Bool) {
        #expect((AppVersion(latest)! > AppVersion(current)!) == newer)
    }

    @Test func invalidVersions() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("beta") == nil)
        #expect(AppVersion("v1.x") == nil)
    }

    let release = #"""
    {"tag_name":"v1.3.0","html_url":"https://github.com/ten50-nl/detour/releases/tag/v1.3.0","body":"- Faster\n- Better","draft":false,"prerelease":false,
     "assets":[{"name":"Detour-1.3.0.dmg","browser_download_url":"https://github.com/ten50-nl/detour/releases/download/v1.3.0/Detour-1.3.0.dmg"},
               {"name":"Detour.dmg","browser_download_url":"https://github.com/ten50-nl/detour/releases/download/v1.3.0/Detour.dmg"}]}
    """#

    @Test func newerReleaseIsOffered() throws {
        let update = try #require(UpdateCheck.evaluate(currentVersion: "1.2.0", releaseJSON: Data(release.utf8)))
        #expect(update.version == "1.3.0")
        #expect(update.downloadURL.absoluteString.hasSuffix("/v1.3.0/Detour-1.3.0.dmg"))
        #expect(update.notes.contains("Faster"))
    }

    @Test func sameOrOlderIsNotOffered() {
        #expect(UpdateCheck.evaluate(currentVersion: "1.3.0", releaseJSON: Data(release.utf8)) == nil)
        #expect(UpdateCheck.evaluate(currentVersion: "1.4.0", releaseJSON: Data(release.utf8)) == nil)
    }

    @Test func prereleasesAndBrokenDataAreIgnored() {
        let pre = release.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
        #expect(UpdateCheck.evaluate(currentVersion: "1.2.0", releaseJSON: Data(pre.utf8)) == nil)
        #expect(UpdateCheck.evaluate(currentVersion: "1.2.0", releaseJSON: Data("{}".utf8)) == nil)
        let noDMG = release.replacingOccurrences(of: ".dmg", with: ".zip")
        #expect(UpdateCheck.evaluate(currentVersion: "1.2.0", releaseJSON: Data(noDMG.utf8)) == nil)
    }

    @Test func onlyGitHubDownloadsAreAccepted() {
        let evil = release.replacingOccurrences(of: "https://github.com/ten50-nl/detour/releases/download", with: "https://evil.example")
        #expect(UpdateCheck.evaluate(currentVersion: "1.2.0", releaseJSON: Data(evil.utf8)) == nil)
    }

    @Test func dueOncePerDay() {
        let now = Date()
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func teamIdentifierParsing() {
        let out = "Executable=/Applications/Detour.app/Contents/MacOS/Detour\nIdentifier=nl.ten50.detour\nTeamIdentifier=8N4S5S7978\nSealed Resources version=2"
        #expect(UpdateCheck.teamIdentifier(fromCodesignOutput: out) == "8N4S5S7978")
        #expect(UpdateCheck.teamIdentifier(fromCodesignOutput: "TeamIdentifier=not set") == nil)
    }
}
