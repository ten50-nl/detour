import Foundation
import Testing
@testable import DetourCore

@Suite struct SuggestionsTests {
    let dests = RulesConfig.fixture.destinations.map { d -> Destination in var d = d; d.patterns = []; return d }

    func index(_ hosts: [String: [DestinationID: Int]]) -> HistoryIndex { HistoryIndex(hosts: hosts) }

    @Test func suggestsStrongNonDefaultHosts() {
        let s = Suggestions.rules(index: index(["tool.example": ["work": 95, "personal": 5]]), destinations: dests, defaultID: "personal")
        #expect(s["work"]?.map(\.host) == ["tool.example"])
        #expect(s["work"]?.first?.visits == 95)
    }

    @Test func skipsDefaultWeakAndRareHosts() {
        let s = Suggestions.rules(index: index([
            "home.example": ["personal": 95, "work": 5],
            "rare.example": ["work": 19],
            "split.example": ["work": 89, "personal": 11],
        ]), destinations: dests, defaultID: "personal")
        #expect(s.values.allSatisfy { $0.isEmpty })
    }

    @Test func topFifteenByVisits() {
        var hosts: [String: [DestinationID: Int]] = [:]
        for i in 0..<20 { hosts["h\(i).example"] = ["work": 100 + i] }
        let s = Suggestions.rules(index: index(hosts), destinations: dests, defaultID: "personal")
        #expect(s["work"]?.count == 15)
        #expect(s["work"]?.first?.host == "h19.example")
    }

    @Test func neverSuggestsAskHostsOrAlreadyCovered() {
        var withPattern = dests
        withPattern[0].patterns = ["covered.example"]
        let s = Suggestions.rules(index: index(["mail.google.com": ["work": 500], "sub.covered.example": ["work": 50]]), destinations: withPattern, defaultID: "personal")
        #expect(s.values.allSatisfy { $0.isEmpty })
    }

    @Test func accountMapFromProfiles() {
        let map = Suggestions.accountMap(destinations: [
            Destination(id: "w", name: "W", appPath: "", bundleID: "", profileDir: "Profile 1", account: "a@acme.com"),
            Destination(id: "p", name: "P", appPath: "", bundleID: "", profileDir: "Default", account: "me@gmail.com"),
        ])
        #expect(map == ["acme.com": "w", "me@gmail.com": "p"])
    }

    @Test func sharedCompanyDomainMapsExactEmailsOnly() {
        let map = Suggestions.accountMap(destinations: [
            Destination(id: "a", name: "A", appPath: "", bundleID: "", profileDir: "Profile 1", account: "a@acme.com"),
            Destination(id: "b", name: "B", appPath: "", bundleID: "", profileDir: "Profile 2", account: "b@acme.com"),
        ])
        #expect(map == ["a@acme.com": "a", "b@acme.com": "b"])
    }

    @Test func videoPresetHasYouTube() {
        #expect(Suggestions.videoPreset.contains("youtube.com"))
        #expect(Suggestions.publicMailDomains.contains("gmail.com"))
    }
}
