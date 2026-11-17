import Foundation
import Testing
@testable import DetourCore

@Suite struct PathLearningTests {
    @Test(arguments: [
        ("https://github.com/acme/api/pull/12", "github.com/acme"),
        ("https://www.github.com/Acme", "github.com/acme"),
        ("https://gitlab.com/acme/web/-/issues", "gitlab.com/acme"),
        ("https://bitbucket.org/acme/repo", "bitbucket.org/acme"),
        ("https://www.notion.so/acme/Roadmap-123", "notion.so/acme"),
        ("https://linear.app/acme/issue/ENG-1", "linear.app/acme"),
        ("https://vercel.com/acme/site", "vercel.com/acme"),
        ("https://www.figma.com/files/team/123/Acme", "figma.com/files/team/123"),
    ])
    func pathKeys(url: String, key: String) {
        #expect(PathKey.key(for: URL(string: url)!) == key)
    }

    @Test(arguments: ["https://github.com/", "https://github.com/settings", "https://github.com/login", "https://example.com/acme", "https://www.figma.com/design/abc/File"])
    func noPathKey(url: String) {
        #expect(PathKey.key(for: URL(string: url)!) == nil)
    }

    @Test func pathHistoryBeatsMixedHost() {
        let h = HistoryIndex(hosts: ["github.com": ["work": 50, "personal": 50]],
                             paths: ["github.com/acme": ["work": 40, "personal": 1], "github.com/me": ["personal": 30]])
        let e = RoutingEngine(rules: .fixture, history: h)
        let work = e.decide(LinkContext(url: URL(string: "https://github.com/acme/api/pull/1")!))
        #expect(work.target == "work")
        #expect(work.stage == .history)
        #expect(work.reason.contains("github.com/acme"))
        #expect(e.decide(LinkContext(url: URL(string: "https://github.com/me/dotfiles")!)).target == "personal")
        #expect(e.decide(LinkContext(url: URL(string: "https://github.com/someone-else/x")!)).askUser)
    }

    @Test func indexerRecordsPaths() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let db = dir.appendingPathComponent("History")
        var inserts = ["INSERT INTO urls (id, url) VALUES (1, 'https://github.com/acme/api')"]
        let t = Int64((Date().addingTimeInterval(-3600).timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
        for i in 0..<6 { inserts.append("INSERT INTO visits (id, url, visit_time) VALUES (\(i + 1), 1, \(t))") }
        try makeHistoryDB(db, inserts: inserts)
        let index = try HistoryIndexer(cacheDir: dir.appendingPathComponent("c")).build(sources: [HistorySource(target: "work", kind: .chrome, dbPath: db)], now: Date())
        #expect(index.paths["github.com/acme"] == ["work": 6])
        #expect(index.hosts["github.com"] == ["work": 6])
    }

    @Test func learnedRemembersPathForSharedHosts() {
        var store = LearnedStore()
        store.remember(url: URL(string: "https://github.com/acme/api")!, target: "work")
        #expect(store.paths["github.com/acme"] == "work")
        #expect(store.hosts["github.com"] == nil)
        #expect(store.lookup(url: URL(string: "https://github.com/acme/other")!)?.0 == "work")
        #expect(store.lookup(url: URL(string: "https://github.com/me/x")!) == nil)
    }

    @Test func oldIndexAndLearnedFilesStillDecode() throws {
        let index = try JSONDecoder().decode(HistoryIndex.self, from: Data(#"{"hosts":{"a.com":{"work":3}},"fileIDs":{},"builtAt":0}"#.utf8))
        #expect(index.paths.isEmpty)
        let learned = try JSONDecoder().decode(LearnedStore.self, from: Data(#"{"hosts":{"a.com":"work"},"fileIDs":{}}"#.utf8))
        #expect(learned.paths.isEmpty)
    }
}
