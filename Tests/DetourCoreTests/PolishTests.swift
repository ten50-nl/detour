import Foundation
import Testing
@testable import DetourCore

@Suite struct PolishTests {
    @Test func pruneDropsReferencesToRemovedDestinations() {
        var rules = RulesConfig.fixture
        rules.destinations.removeAll { $0.id == "work" }
        let pruned = rules.pruned()
        #expect(pruned.accountMap["acme.com"] == nil)
        #expect(pruned.accountMap["me@gmail.com"] == "personal")
        #expect(!pruned.sourceRules.contains { $0.target == "work" })
        #expect(pruned.sourceRules.count == 1)
    }

    @Test func pruneRepairsDanglingDefault() {
        var rules = RulesConfig.fixture
        rules.defaultDestination = "gone"
        #expect(rules.pruned().defaultDestination == "work")
    }

    @Test func engineFallsBackToFirstDestinationWhenDefaultDangles() {
        var rules = RulesConfig.fixture
        rules.defaultDestination = "gone"
        let d = RoutingEngine(rules: rules).decide(LinkContext(url: URL(string: "https://unknown.example/")!))
        #expect(d.target == "work")
    }

    @Test func learnedPruneKeepsOnlyValidTargets() {
        let learned = LearnedStore(hosts: ["a.com": "work", "b.com": "gone"], fileIDs: ["x": "gone", "y": "personal"])
        let pruned = learned.pruned(validIDs: ["work", "personal"])
        #expect(pruned.hosts == ["a.com": "work"])
        #expect(pruned.fileIDs == ["y": "personal"])
    }

    @Test func duplicateNamesGetBrowserAndProfile() {
        var rules = RulesConfig.fixture
        rules.destinations[0].name = "Personal"
        let names = rules.displayNames()
        #expect(names["work"] == "Personal (Google Chrome, Profile 1)")
        #expect(names["personal"] == "Personal (Google Chrome, Default)")
        #expect(names["ads"] == "Ad-free")
    }

    @Test func countryMailDomainsArePublic() {
        for domain in ["hotmail.nl", "live.nl", "outlook.de", "yahoo.co.uk", "web.de", "gmx.de", "icloud.com", "ziggo.nl", "kpnmail.nl"] {
            #expect(Suggestions.publicMailDomains.contains(domain), "\(domain)")
        }
    }

    @Test func profileWarningNamesTheRightBrowser() {
        let brave = Destination(id: "b", name: "B", appPath: "/Applications/Brave Browser.app", bundleID: "com.brave.Browser", profileDir: "Profile 1", profileName: "Old")
        let problems = ProfileCheck.problems(destinations: [brave], names: ["Profile 1": "New"])
        #expect(problems["b"]?.message.contains("Brave Browser") == true)
        #expect(problems["b"]?.message.contains("Chrome") == false)
    }

    @Test func staleHistoryCopiesAreRemoved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stale = dir.appendingPathComponent("leftover-History")
        try Data("old".utf8).write(to: stale)
        _ = try HistoryIndexer(cacheDir: dir).build(sources: [], now: Date())
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }
}
