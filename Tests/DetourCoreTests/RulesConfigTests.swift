import Foundation
import Testing
@testable import DetourCore

@Suite struct RulesConfigTests {
    @Test func fixtureRoundTrips() throws {
        let data = try JSONEncoder().encode(RulesConfig.fixture)
        let decoded = try JSONDecoder().decode(RulesConfig.self, from: data)
        #expect(decoded == RulesConfig.fixture)
        #expect(decoded.version == 2)
    }

    @Test func emptyHasNoPersonalData() {
        let empty = RulesConfig.empty
        #expect(empty.destinations.isEmpty)
        #expect(empty.accountMap.isEmpty)
        #expect(empty.sourceRules.isEmpty)
        #expect(empty.askHosts == ["docs.google.com", "drive.google.com", "mail.google.com", "calendar.google.com", "meet.google.com"])
    }

    @Test func destinationLookup() {
        #expect(RulesConfig.fixture.destination("ads")?.name == "Ad-free")
        #expect(RulesConfig.fixture.destination("nope") == nil)
    }

    @Test func invalidFileKeepsFallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data("{not json".utf8).write(to: url)
        let (rules, error) = ConfigLoader.loadRules(from: url, fallback: .fixture)
        #expect(rules == .fixture)
        #expect(error != nil)
    }

    @Test func missingFileReturnsFallbackWithoutWriting() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("rules.json")
        let (rules, error) = ConfigLoader.loadRules(from: url, fallback: .empty)
        #expect(error == nil)
        #expect(rules == .empty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
