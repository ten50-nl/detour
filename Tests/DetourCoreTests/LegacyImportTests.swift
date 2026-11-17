import Foundation
import Testing
@testable import DetourCore

@Suite struct LegacyImportTests {
    let v1 = """
    {
      "accountMap": {"acme.com": "work", "gmail.com": "personal"},
      "ambiguousHosts": ["docs.google.com", "dash.cloudflare.com"],
      "work": ["~acme", "meet.google.com"],
      "firefox": ["youtube.com", "ppv.*"],
      "personal": ["linkedin.com", "news.example"],
      "sourceRules": [{"app": "Ferdium", "target": "work", "titleContains": "Mattermost"}],
      "targets": [
        {"appPath": "/Applications/Google Chrome.app", "chromeProfileDir": "Profile 3", "expectedProfileName": "Work", "id": "work", "label": "Work"},
        {"appPath": "/Applications/Google Chrome.app", "chromeProfileDir": "Default", "expectedProfileName": "Me", "id": "personal", "label": "Personal"},
        {"appPath": "/Applications/Firefox.app", "id": "firefox", "label": "Firefox"}
      ]
    }
    """

    @Test func importsDestinationsInPrecedenceOrder() throws {
        let rules = try LegacyImport.rules(fromV1: Data(v1.utf8))
        #expect(rules.version == 2)
        #expect(rules.destinations.map(\.id) == ["work", "firefox", "personal"])
        #expect(rules.destinations.map(\.name) == ["Work", "Firefox", "Personal"])
        #expect(rules.destination("work")?.profileDir == "Profile 3")
        #expect(rules.destination("work")?.profileName == "Work")
        #expect(rules.destination("work")?.bundleID == "com.google.Chrome")
        #expect(rules.destination("firefox")?.bundleID == "org.mozilla.firefox")
        #expect(rules.destination("firefox")?.profileDir == nil)
        #expect(rules.defaultDestination == "personal")
    }

    @Test func keepsEveryPatternAndSetting() throws {
        let rules = try LegacyImport.rules(fromV1: Data(v1.utf8))
        #expect(rules.destination("work")?.patterns == ["~acme", "meet.google.com"])
        #expect(rules.destination("firefox")?.patterns == ["youtube.com", "ppv.*"])
        #expect(rules.destination("personal")?.patterns == ["linkedin.com", "news.example"])
        #expect(rules.askHosts == ["docs.google.com", "dash.cloudflare.com"])
        #expect(rules.accountMap == ["acme.com": "work", "gmail.com": "personal"])
        #expect(rules.sourceRules == [SourceRule(app: "Ferdium", titleContains: "Mattermost", target: "work")])
    }

    @Test func configLoaderMigratesV1() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(v1.utf8).write(to: url)
        let (rules, error) = ConfigLoader.loadRules(from: url, fallback: .empty)
        #expect(error == nil)
        #expect(rules.destinations.count == 3)
    }

    @Test func learnedV1Decodes() throws {
        let data = Data(#"{"hosts":{"a.com":"work"},"fileIDs":{"1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms":"personal"}}"#.utf8)
        let learned = try LegacyImport.learned(fromV1: data)
        #expect(learned.hosts["a.com"] == "work")
        #expect(learned.fileIDs.count == 1)
    }

    @Test func extraTargetsKeepTheirListsAndPersonalGoesLast() throws {
        let json = """
        {"accountMap": {}, "ambiguousHosts": [], "sourceRules": [],
         "personal": ["a.example"], "side": ["b.example"], "work": ["c.example"],
         "targets": [
           {"appPath": "/Applications/Google Chrome.app", "chromeProfileDir": "Default", "id": "personal", "label": "Personal"},
           {"appPath": "/Applications/Google Chrome.app", "chromeProfileDir": "Profile 2", "id": "work", "label": "Work"},
           {"appPath": "/Applications/Safari.app", "id": "side", "label": "Side"}
         ]}
        """
        let rules = try LegacyImport.rules(fromV1: Data(json.utf8))
        #expect(rules.destinations.map(\.id) == ["work", "side", "personal"])
        #expect(rules.destination("side")?.patterns == ["b.example"])
        #expect(rules.defaultDestination == "personal")
    }

    @Test func noPersonalTargetDefaultsToLast() throws {
        let json = #"{"accountMap":{},"ambiguousHosts":[],"sourceRules":[],"work":[],"targets":[{"appPath":"/Applications/Safari.app","id":"work","label":"Work"}]}"#
        let rules = try LegacyImport.rules(fromV1: Data(json.utf8))
        #expect(rules.defaultDestination == "work")
    }

    @Test func garbageIsAnError() {
        #expect(throws: (any Error).self) { try LegacyImport.rules(fromV1: Data("{}".utf8)) }
    }
}
