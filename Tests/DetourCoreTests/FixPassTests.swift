import Foundation
import Testing
@testable import DetourCore

@Suite struct FixPassTests {
    @Test func parsesMessyLinksKeepingFragment() {
        #expect(LinkParser.parse("https://example.com/a b#section")?.absoluteString == "https://example.com/a%20b#section")
        #expect(LinkParser.parse("  https://example.com/x  ")?.absoluteString == "https://example.com/x")
        #expect(LinkParser.parse("https://exämple.com/ü")?.host() != nil)
        #expect(LinkParser.parse("") == nil)
    }

    @Test func detectsInPlaceRewrite() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("a".utf8).write(to: url)
        var detector = FileChangeDetector(url: url)
        let first = detector.hasChanged()
        #expect(!first)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("bb".utf8))
        try handle.close()
        let second = detector.hasChanged()
        let third = detector.hasChanged()
        #expect(second)
        #expect(!third)
    }

    @Test func openChainDedupes() {
        #expect(openChain("work", default: "personal") == ["work", "personal"])
        #expect(openChain("personal", default: "personal") == ["personal"])
    }

    @Test func titleProviderNotCalledWhenRuleDecides() {
        final class Counter: @unchecked Sendable { var calls = 0 }
        let counter = Counter()
        let engine = RoutingEngine(rules: .fixture)
        let ctx = LinkContext(url: URL(string: "https://git.acme.io/")!, sourceApp: "Ferdium", titleProvider: { counter.calls += 1; return "Ferdium - Mattermost" })
        _ = engine.decide(ctx)
        #expect(counter.calls == 0)
        let ambiguous = LinkContext(url: URL(string: "https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit")!, sourceApp: "Ferdium", titleProvider: { counter.calls += 1; return "Ferdium - Mattermost - x" })
        #expect(engine.decide(ambiguous).target == "work")
        #expect(counter.calls == 1)
    }
}
