import Foundation
import Testing
@testable import DetourCore

@Suite struct RewriteTests {
    private func rewrite(_ input: String, _ rules: [RewriteRule]) -> String {
        LinkRewriter.rewrite(URL(string: input)!, rules: rules).absoluteString
    }

    @Test func replacesHostAndKeepsPathQueryAndFragment() {
        let rules = [RewriteRule(from: "x.com", to: "xcancel.com")]
        #expect(rewrite("https://x.com/jack/status/20?s=1#top", rules) == "https://xcancel.com/jack/status/20?s=1#top")
    }

    @Test func matchesWwwAndSubdomains() {
        let rules = [RewriteRule(from: "reddit.com", to: "old.reddit.com")]
        #expect(rewrite("https://www.reddit.com/r/macapps/", rules) == "https://old.reddit.com/r/macapps/")
        #expect(rewrite("https://new.reddit.com/r/macapps/", rules) == "https://old.reddit.com/r/macapps/")
        #expect(rewrite("https://old.reddit.com/r/macapps/", rules) == "https://old.reddit.com/r/macapps/")
    }

    @Test func leavesLookalikeHostsAlone() {
        let rules = [RewriteRule(from: "x.com", to: "xcancel.com")]
        #expect(rewrite("https://box.com/file", rules) == "https://box.com/file")
        #expect(rewrite("https://x.company.test/", rules) == "https://x.company.test/")
    }

    @Test func firstMatchingRuleWins() {
        let rules = [RewriteRule(from: "twitter.com", to: "xcancel.com"), RewriteRule(from: "twitter.com", to: "nitter.test")]
        #expect(rewrite("https://twitter.com/a", rules) == "https://xcancel.com/a")
    }

    @Test func noRulesKeepsTheLink() {
        #expect(rewrite("http://example.com/a", []) == "http://example.com/a")
    }

    @Test func normalizesWhatPeopleType() {
        #expect(RewriteRule.make(from: " https://www.X.com/ ", to: "XCancel.com/") == RewriteRule(from: "x.com", to: "xcancel.com"))
        #expect(RewriteRule.make(from: "x.com", to: "") == nil)
        #expect(RewriteRule.make(from: "x.com", to: "x.com") == nil)
        #expect(RewriteRule.make(from: "not a host", to: "xcancel.com") == nil)
    }

    @Test func prepareRewritesThenCleans() {
        var config = RulesConfig(destinations: [], defaultDestination: "")
        config.rewrites = [RewriteRule(from: "x.com", to: "xcancel.com")]
        #expect(config.prepare(URL(string: "https://x.com/a?utm_source=b")!).absoluteString == "https://xcancel.com/a")
        config.cleanLinks = false
        #expect(config.prepare(URL(string: "https://x.com/a?utm_source=b")!).absoluteString == "https://xcancel.com/a?utm_source=b")
    }

    @Test func oldConfigFilesDecodeWithoutRewrites() throws {
        let json = #"{"destinations":[],"defaultDestination":""}"#
        let config = try JSONDecoder().decode(RulesConfig.self, from: Data(json.utf8))
        #expect(config.rewrites.isEmpty)
    }

    @Test func rewritesSurviveARoundTrip() throws {
        var config = RulesConfig(destinations: [], defaultDestination: "")
        config.rewrites = [RewriteRule(from: "reddit.com", to: "old.reddit.com")]
        let decoded = try JSONDecoder().decode(RulesConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.rewrites == config.rewrites)
    }
}

@Suite struct SettingsImportTests {
    @Test func importsAnExportedFile() throws {
        var config = RulesConfig.fixture
        config.rewrites = [RewriteRule(from: "x.com", to: "xcancel.com")]
        let encoder = JSONEncoder()
        let imported = try ConfigLoader.importRules(from: encoder.encode(config))
        #expect(imported == config)
    }

    @Test func rejectsFilesThatAreNotDetourSettings() {
        #expect(throws: ConfigLoader.ImportError.notDetourSettings) { try ConfigLoader.importRules(from: Data(#"{"hello":1}"#.utf8)) }
        #expect(throws: ConfigLoader.ImportError.notDetourSettings) { try ConfigLoader.importRules(from: Data("not json".utf8)) }
    }

    @Test func rejectsSettingsWithoutDestinations() {
        let json = #"{"destinations":[],"defaultDestination":""}"#
        #expect(throws: ConfigLoader.ImportError.noDestinations) { try ConfigLoader.importRules(from: Data(json.utf8)) }
    }
}
