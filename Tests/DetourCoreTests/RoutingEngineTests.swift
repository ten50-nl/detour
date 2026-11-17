import Foundation
import Testing
@testable import DetourCore

@Suite struct RoutingEngineTests {
    let docID = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"

    func ctx(_ url: String, app: String? = nil, title: String? = nil, force: Bool = false) -> LinkContext {
        LinkContext(url: URL(string: url)!, sourceApp: app, sourceWindowTitle: title, forcePicker: force)
    }

    func engine(history: HistoryIndex? = nil, learned: LearnedStore = LearnedStore(), rules: RulesConfig = .fixture) -> RoutingEngine {
        RoutingEngine(rules: rules, learned: learned, history: history)
    }

    @Test func forcedAsks() {
        let d = engine().decide(ctx("https://git.acme.io/", force: true))
        #expect(d.askUser)
        #expect(d.stage == .forced)
        #expect(d.target == "work")
    }

    @Test func ruleWork() {
        let d = engine().decide(ctx("https://acme-corp.atlassian.net/browse/X-1"))
        #expect(d.target == "work")
        #expect(d.stage == .rule)
        #expect(!d.askUser)
    }

    @Test func destinationOrderWins() {
        var rules = RulesConfig.fixture
        rules.destinations[2].patterns.append("youtube.com")
        #expect(engine(rules: rules).decide(ctx("https://youtube.com/watch?v=1")).target == "ads")
        rules.destinations.swapAt(1, 2)
        #expect(engine(rules: rules).decide(ctx("https://youtube.com/watch?v=1")).target == "personal")
    }

    @Test func ruleAds() {
        #expect(engine().decide(ctx("https://www.youtube.com/watch?v=x")).target == "ads")
        #expect(engine().decide(ctx("https://www.dumpert.nl/item/1")).target == "ads")
    }

    @Test func ruleSocialPersonal() {
        let d = engine().decide(ctx("https://www.linkedin.com/company/acme"))
        #expect(d.target == "personal")
        #expect(d.stage == .rule)
    }

    @Test func calendarDecoded() {
        let eid = base64url("abc colleague@acme.com")
        let d = engine().decide(ctx("https://calendar.google.com/calendar/event?eid=\(eid)"))
        #expect(d.target == "work")
        #expect(d.stage == .decoder)
        #expect(!d.askUser)
    }

    @Test func exactEmailBeatsDomain() {
        var rules = RulesConfig.fixture
        rules.accountMap["boss@acme.com"] = "personal"
        let e = engine(rules: rules)
        #expect(e.decide(ctx("https://calendar.google.com/calendar/event?eid=\(base64url("x boss@acme.com"))")).target == "personal")
        #expect(e.decide(ctx("https://calendar.google.com/calendar/event?eid=\(base64url("x other@acme.com"))")).target == "work")
        #expect(e.decide(ctx("https://calendar.google.com/calendar/event?eid=\(base64url("x me@m"))")).target == "personal")
    }

    @Test func docsUnknownAsks() {
        let d = engine().decide(ctx("https://docs.google.com/document/d/\(docID)/edit"))
        #expect(d.askUser)
        #expect(d.target == "personal")
        #expect(d.stage == .ambiguous)
    }

    @Test func docsKnownFile() {
        let d = engine(history: HistoryIndex(fileIDs: [docID: ["work"]])).decide(ctx("https://docs.google.com/document/d/\(docID)/edit"))
        #expect(d.target == "work")
        #expect(d.stage == .decoder)
    }

    @Test func learnedBeatsHistory() {
        let d = engine(history: HistoryIndex(hosts: ["shop.example": ["work": 10]]), learned: LearnedStore(hosts: ["shop.example": "ads"])).decide(ctx("https://shop.example/"))
        #expect(d.target == "ads")
        #expect(d.stage == .learned)
    }

    @Test func historyConfident() {
        let d = engine(history: HistoryIndex(hosts: ["tool.example": ["work": 9, "personal": 1]])).decide(ctx("https://tool.example/x"))
        #expect(d.target == "work")
        #expect(d.stage == .history)
    }

    @Test func mixedWithSourceRule() {
        let d = engine(history: HistoryIndex(hosts: ["shared.example": ["work": 5, "personal": 5]])).decide(ctx("https://shared.example/", app: "Ferdium", title: "Ferdium - Mattermost - x"))
        #expect(d.target == "work")
        #expect(d.stage == .source)
    }

    @Test func mixedNoSourceAsks() {
        let d = engine(history: HistoryIndex(hosts: ["shared.example": ["work": 6, "personal": 4]])).decide(ctx("https://shared.example/", app: "Terminal"))
        #expect(d.askUser)
        #expect(d.target == "work")
    }

    @Test func unknownHostGoesToDefaultDestination() {
        var rules = RulesConfig.fixture
        rules.defaultDestination = "ads"
        let d = engine(rules: rules).decide(ctx("https://random-shop.example/"))
        #expect(d.target == "ads")
        #expect(!d.askUser)
        #expect(d.stage == .fallback)
    }

    @Test func weirdSchemeFallsBack() {
        let d = engine().decide(ctx("ftp://x/"))
        #expect(d.target == "personal")
        #expect(!d.askUser)
    }

    @Test func emptyConfigStillRoutesSomewhere() {
        let d = engine(rules: .empty).decide(ctx("https://example.com/"))
        #expect(d.target == "")
        #expect(!d.askUser)
    }

    @Test func decisionIsFast() {
        var hosts: [String: [DestinationID: Int]] = [:]
        for i in 0..<5000 { hosts["host\(i).example"] = ["work": i % 7, "personal": 5] }
        let e = engine(history: HistoryIndex(hosts: hosts))
        let urls = (0..<1000).map { ctx("https://host\($0 * 5).example/path?q=\($0)") }
        let start = Date()
        for c in urls { _ = e.decide(c) }
        #expect(Date().timeIntervalSince(start) < 0.15)
    }
}
