import Foundation
import Testing
@testable import DetourCore

@Suite struct LinkCleanerTests {
    @Test(arguments: [
        ("https://example.com/a?utm_source=x&utm_medium=y&id=5", "https://example.com/a?id=5"),
        ("https://example.com/a?fbclid=abc", "https://example.com/a"),
        ("https://example.com/a?gclid=1&msclkid=2&mc_cid=3&mc_eid=4#top", "https://example.com/a#top"),
        ("https://www.youtube.com/watch?v=abc&si=track", "https://www.youtube.com/watch?v=abc"),
        ("https://youtu.be/abc?si=track", "https://youtu.be/abc"),
        ("https://example.com/a?si=keep", "https://example.com/a?si=keep"),
        ("https://example.com/a?q=utm_source", "https://example.com/a?q=utm_source"),
        ("https://example.com/a", "https://example.com/a"),
    ])
    func cleans(input: String, output: String) {
        #expect(LinkCleaner.clean(URL(string: input)!).absoluteString == output)
    }
}

@Suite struct AppLinkTests {
    @Test func zoomMeeting() {
        let link = AppLinks.convert(URL(string: "https://acme.zoom.us/j/123456789?pwd=abcDEF")!)
        #expect(link?.app == "Zoom")
        #expect(link?.url.absoluteString == "zoommtg://zoom.us/join?action=join&confno=123456789&pwd=abcDEF")
    }

    @Test func zoomWithoutPassword() {
        #expect(AppLinks.convert(URL(string: "https://zoom.us/j/987")!)?.url.absoluteString == "zoommtg://zoom.us/join?action=join&confno=987")
    }

    @Test func teamsMeeting() {
        let link = AppLinks.convert(URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d")!)
        #expect(link?.app == "Microsoft Teams")
        #expect(link?.url.absoluteString == "msteams:/l/meetup-join/19%3ameeting_x%40thread.v2/0?context=%7b%7d")
    }

    @Test func slackChannel() {
        let link = AppLinks.convert(URL(string: "https://app.slack.com/client/T0123/C0456")!)
        #expect(link?.app == "Slack")
        #expect(link?.url.absoluteString == "slack://channel?team=T0123&id=C0456")
    }

    @Test(arguments: ["https://zoom.us/pricing", "https://teams.microsoft.com/", "https://app.slack.com/", "https://example.com/j/1"])
    func notAppLinks(url: String) {
        #expect(AppLinks.convert(URL(string: url)!) == nil)
    }

    @Test func engineOpensInAppOnlyWhenEnabledAndInstalled() {
        var rules = RulesConfig.fixture
        let url = URL(string: "https://acme.zoom.us/j/1")!
        var engine = RoutingEngine(rules: rules)
        engine.appAvailable = { _ in true }
        #expect(engine.decide(LinkContext(url: url)).stage != .app)
        rules.openInApps = true
        engine.rules = rules
        let d = engine.decide(LinkContext(url: url))
        #expect(d.stage == .app)
        #expect(d.appURL?.scheme == "zoommtg")
        engine.appAvailable = { _ in false }
        #expect(engine.decide(LinkContext(url: url)).stage != .app)
    }

    @Test func settingsDecodeWithDefaults() throws {
        let data = try JSONEncoder().encode(RulesConfig.fixture)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "openInApps")
        dict.removeValue(forKey: "cleanLinks")
        let decoded = try JSONDecoder().decode(RulesConfig.self, from: JSONSerialization.data(withJSONObject: dict))
        #expect(decoded.openInApps == false)
        #expect(decoded.cleanLinks == true)
    }
}

@Suite struct PrivateWindowTests {
    let chrome = Destination(id: "c", name: "Chrome", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome", profileDir: "Profile 1")
    let firefox = Destination(id: "f", name: "Firefox", appPath: "/Applications/Firefox.app", bundleID: "org.mozilla.firefox")
    let url = URL(string: "https://example.com/")!

    @Test func profileArguments() {
        #expect(LaunchArguments.arguments(for: chrome, url: url) == ["--profile-directory=Profile 1", "https://example.com/"])
    }

    @Test func chromiumIncognito() {
        var d = chrome
        d.privateWindow = true
        #expect(LaunchArguments.arguments(for: d, url: url) == ["--profile-directory=Profile 1", "--incognito", "https://example.com/"])
    }

    @Test func firefoxPrivate() {
        var d = firefox
        d.privateWindow = true
        #expect(LaunchArguments.arguments(for: d, url: url) == ["-private-window", "https://example.com/"])
    }

    @Test func plainBrowserHasNoArguments() {
        #expect(LaunchArguments.arguments(for: firefox, url: url) == nil)
    }

    @Test func privateSupport() {
        #expect(LaunchArguments.supportsPrivate(chrome))
        #expect(LaunchArguments.supportsPrivate(firefox))
        #expect(!LaunchArguments.supportsPrivate(Destination(id: "s", name: "Safari", appPath: "/Applications/Safari.app", bundleID: "com.apple.Safari")))
    }

    @Test func oldDestinationsDecodeWithoutPrivateFlag() throws {
        let d = try JSONDecoder().decode(Destination.self, from: Data(##"{"id":"x","name":"X","appPath":"/a","bundleID":"b","color":"#000000","patterns":[]}"##.utf8))
        #expect(d.privateWindow == false)
    }
}

@Suite struct MoreAppLinkTests {
    @Test(arguments: [
        ("https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=abc", "Spotify", "spotify:track:4uLU6hMCjMI75M1A2tKUQC"),
        ("https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M", "Spotify", "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"),
        ("https://music.apple.com/nl/album/abbey-road/1441164426", "Music", "music://music.apple.com/nl/album/abbey-road/1441164426"),
        ("https://discord.com/channels/123/456", "Discord", "discord://-/channels/123/456"),
        ("https://discord.gg/abcDEF", "Discord", "discord://-/invite/abcDEF"),
        ("https://linear.app/acme/issue/ENG-12/fix-it", "Linear", "linear://acme/issue/ENG-12/fix-it"),
        ("https://www.notion.so/acme/Roadmap-0123456789abcdef", "Notion", "notion://www.notion.so/acme/Roadmap-0123456789abcdef"),
    ])
    func converts(url: String, app: String, expected: String) {
        let link = AppLinks.convert(URL(string: url)!)
        #expect(link?.app == app)
        #expect(link?.url.absoluteString == expected)
    }

    @Test(arguments: ["https://open.spotify.com/", "https://linear.app/", "https://linear.app/login", "https://www.notion.so/", "https://discord.com/", "https://music.apple.com/"])
    func ignoresNonContentPages(url: String) {
        #expect(AppLinks.convert(URL(string: url)!) == nil)
    }
}
