import Foundation
import Testing
@testable import DetourCore

@Suite struct LearnedAndHistoryTests {
    let docURL = URL(string: "https://docs.google.com/document/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit")!

    @Test func learnedPrefersFileID() {
        var store = LearnedStore()
        store.remember(url: docURL, target: "work")
        #expect(store.fileIDs["1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"] == "work")
        #expect(store.hosts["docs.google.com"] == nil)
        #expect(store.lookup(url: docURL)?.0 == "work")
        let other = URL(string: "https://docs.google.com/document/d/2ZZZZZZZZZZZZZZZZZZZZZZZZZZZZ/edit")!
        #expect(store.lookup(url: other) == nil)
    }

    @Test func learnedHost() {
        var store = LearnedStore()
        store.remember(url: URL(string: "https://www.Example.org/a")!, target: "ads")
        #expect(store.lookup(url: URL(string: "https://example.org/b")!)?.0 == "ads")
        #expect(store.lookup(url: URL(string: "https://sub.example.org/b")!) == nil)
    }

    func index(_ counts: [DestinationID: Int]) -> HistoryIndex {
        HistoryIndex(hosts: ["h.com": counts], fileIDs: [:], builtAt: Date())
    }

    @Test func verdictConfident() {
        #expect(index(["work": 8, "personal": 2]).hostVerdict("h.com") == .confident("work", share: 0.8, total: 10))
    }

    @Test func verdictMixed() {
        #expect(index(["work": 7, "personal": 3]).hostVerdict("h.com") == .mixed(counts: ["work": 7, "personal": 3]))
    }

    @Test func verdictTooFew() {
        #expect(index(["work": 4]).hostVerdict("h.com") == .mixed(counts: ["work": 4]))
    }

    @Test func verdictNone() {
        #expect(index(["work": 4]).hostVerdict("other.com") == HostVerdict.none)
    }

    @Test func fileTargetSingleOnly() {
        let idx = HistoryIndex(hosts: [:], fileIDs: ["a": ["work"], "b": ["work", "personal"]], builtAt: Date())
        #expect(idx.fileTarget("a") == "work")
        #expect(idx.fileTarget("b") == nil)
        #expect(idx.fileTarget("c") == nil)
    }

    @Test func historyIndexRoundTrips() throws {
        let idx = HistoryIndex(hosts: ["h.com": ["work": 3]], fileIDs: ["a": ["personal"]], builtAt: Date(timeIntervalSince1970: 1000))
        let decoded = try JSONDecoder().decode(HistoryIndex.self, from: JSONEncoder().encode(idx))
        #expect(decoded == idx)
    }
}
