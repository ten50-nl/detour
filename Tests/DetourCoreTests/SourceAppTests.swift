import Foundation
import Testing
@testable import DetourCore

@Suite struct SourceAppTests {
    func ctx(_ url: String, app: String?) -> LinkContext {
        LinkContext(url: URL(string: url)!, sourceApp: app)
    }

    func rules(_ extra: [SourceRule]) -> RulesConfig {
        var r = RulesConfig.fixture
        r.sourceRules = extra
        return r
    }

    @Test func oldSourceRulesDecodeAsTieBreaker() throws {
        let rule = try JSONDecoder().decode(SourceRule.self, from: Data(#"{"app":"Slack","target":"work"}"#.utf8))
        #expect(rule.strength == .tieBreaker)
    }

    @Test func tieBreakerDoesNotRouteUnknownSites() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work", strength: .tieBreaker)]))
        #expect(e.decide(ctx("https://never-seen.example/", app: "Slack")).stage == .fallback)
    }

    @Test func tieBreakerSettlesMixedAndAskSites() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work", strength: .tieBreaker)]),
                              history: HistoryIndex(hosts: ["shared.example": ["work": 5, "personal": 5]]))
        #expect(e.decide(ctx("https://shared.example/", app: "Slack")).target == "work")
        #expect(e.decide(ctx("https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit", app: "Slack")).target == "work")
        #expect(!e.decide(ctx("https://shared.example/", app: "Slack")).askUser)
    }

    @Test func newRulesDefaultToWhenUnsure() {
        #expect(SourceRule(app: "Slack", target: "work").strength == .whenUnsure)
    }

    @Test func alwaysBeatsHistory() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work", strength: .always)]),
                              history: HistoryIndex(hosts: ["news.example": ["personal": 50]]))
        let d = e.decide(ctx("https://news.example/a", app: "Slack"))
        #expect(d.target == "work")
        #expect(d.stage == .source)
    }

    @Test func siteRuleBeatsAlways() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work", strength: .always)]))
        #expect(e.decide(ctx("https://www.youtube.com/watch?v=1", app: "Slack")).target == "ads")
    }

    @Test func whenUnsureDoesNotBeatClearHistory() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work")]),
                              history: HistoryIndex(hosts: ["news.example": ["personal": 50]]))
        #expect(e.decide(ctx("https://news.example/a", app: "Slack")).target == "personal")
    }

    @Test func whenUnsureRoutesUnknownSites() {
        let e = RoutingEngine(rules: rules([SourceRule(app: "Slack", target: "work")]))
        let d = e.decide(ctx("https://never-seen.example/", app: "Slack"))
        #expect(d.target == "work")
        #expect(d.stage == .source)
        #expect(!d.askUser)
        #expect(e.decide(ctx("https://never-seen.example/", app: "Mail")).stage == .fallback)
    }

    @Test func learnedTendencyRoutesUnknownSites() {
        let entries = Array(repeating: AppTendencies.Entry(app: "Slack", target: "work", stage: .rule), count: 18)
            + Array(repeating: AppTendencies.Entry(app: "Slack", target: "personal", stage: .history), count: 2)
        var e = RoutingEngine(rules: rules([]))
        e.tendencies = AppTendencies(entries: entries)
        let d = e.decide(ctx("https://never-seen.example/", app: "Slack"))
        #expect(d.target == "work")
        #expect(d.stage == .source)
        #expect(d.reason.contains("90%"))
    }

    @Test func tendencyNeedsEnoughClearLinks() {
        let few = Array(repeating: AppTendencies.Entry(app: "Slack", target: "work", stage: .rule), count: 9)
        #expect(AppTendencies(entries: few).target(for: "Slack") == nil)
        let split = Array(repeating: AppTendencies.Entry(app: "Slack", target: "work", stage: .rule), count: 16)
            + Array(repeating: AppTendencies.Entry(app: "Slack", target: "personal", stage: .rule), count: 4)
        #expect(AppTendencies(entries: split).target(for: "Slack") == nil)
    }

    @Test func tendencyIgnoresDefaultsAndItsOwnDecisions() {
        let noisy = Array(repeating: AppTendencies.Entry(app: "Slack", target: "personal", stage: .fallback), count: 30)
            + Array(repeating: AppTendencies.Entry(app: "Slack", target: "work", stage: .source), count: 30)
        #expect(AppTendencies(entries: noisy).target(for: "Slack") == nil)
    }

    @Test func tendencyIsCaseInsensitiveAndSkipsDetour() {
        let entries = Array(repeating: AppTendencies.Entry(app: "slack", target: "work", stage: .learned), count: 12)
            + Array(repeating: AppTendencies.Entry(app: "Detour", target: "work", stage: .rule), count: 12)
        let t = AppTendencies(entries: entries)
        #expect(t.target(for: "Slack")?.target == "work")
        #expect(t.target(for: "Detour") == nil)
    }

    @Test func suggestsChatAppRules() {
        let s = Suggestions.appRules(installedApps: ["Slack", "Microsoft Teams", "Messages", "WhatsApp", "Safari"],
                                     destinations: RulesConfig.fixture.destinations, defaultID: "personal", existing: [])
        #expect(s.contains(SourceRule(app: "Slack", target: "work")))
        #expect(s.contains(SourceRule(app: "Microsoft Teams", target: "work")))
        #expect(s.contains(SourceRule(app: "Messages", target: "personal")))
        #expect(s.contains(SourceRule(app: "WhatsApp", target: "personal")))
        #expect(!s.contains { $0.app == "Safari" })
    }

    @Test func noWorkDestinationMeansNoWorkAppSuggestions() {
        var dests = RulesConfig.fixture.destinations
        dests[0].account = "me@gmail.com"
        let s = Suggestions.appRules(installedApps: ["Slack", "Messages"], destinations: dests, defaultID: "personal", existing: [])
        #expect(!s.contains { $0.app == "Slack" })
        #expect(s.contains { $0.app == "Messages" })
    }

    @Test func existingAppRulesAreNotSuggestedAgain() {
        let s = Suggestions.appRules(installedApps: ["Slack"], destinations: RulesConfig.fixture.destinations, defaultID: "personal",
                                     existing: [SourceRule(app: "slack", target: "ads")])
        #expect(s.isEmpty)
    }
}

@Suite struct TendencyDriftTests {
    func entries(_ app: String, _ target: DestinationID, _ n: Int) -> [AppTendencies.Entry] {
        Array(repeating: AppTendencies.Entry(app: app, target: target, stage: .rule), count: n)
    }

    @Test func onlyRecentLinksCount() {
        let t = AppTendencies(entries: entries("Slack", "personal", 60) + entries("Slack", "work", 50))
        #expect(t.target(for: "Slack")?.target == "work")
        #expect(t.target(for: "Slack")?.total == AppTendencies.window)
    }

    @Test func driftingClicksBackOff() {
        let t = AppTendencies(entries: entries("Slack", "work", 40) + entries("Slack", "personal", 20))
        #expect(t.target(for: "Slack") == nil)
    }

    @Test func forgetStartsFresh() {
        var t = AppTendencies(entries: entries("Slack", "work", 30))
        t.forget(app: "slack")
        #expect(t.target(for: "Slack") == nil)
        for e in entries("Slack", "personal", 12) { t.add(e) }
        #expect(t.target(for: "Slack")?.target == "personal")
    }
}
