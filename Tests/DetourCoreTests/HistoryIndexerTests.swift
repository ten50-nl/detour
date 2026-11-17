import Foundation
import SQLite3
import Testing
@testable import DetourCore

private func makeDB(_ path: URL, schema: String, inserts: [String]) throws {
    var db: OpaquePointer?
    try #require(sqlite3_open(path.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    for sql in [schema] + inserts {
        try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    }
}

@Suite struct HistoryIndexerTests {
    let docID = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"

    func chromeTime(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) }
    func firefoxTime(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1_000_000) }

    @Test func buildsFromChromeAndFirefox() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let recent = now.addingTimeInterval(-86_400)
        let old = now.addingTimeInterval(-100 * 86_400)

        let chrome = dir.appendingPathComponent("History")
        var chromeInserts = [
            "INSERT INTO urls (id, url) VALUES (1, 'https://my.hosting.com/dashboard')",
            "INSERT INTO urls (id, url) VALUES (2, 'https://docs.google.com/document/d/\(docID)/edit')",
            "INSERT INTO urls (id, url) VALUES (3, 'https://old.example/')",
        ]
        for i in 0..<6 { chromeInserts.append("INSERT INTO visits (id, url, visit_time) VALUES (\(10 + i), 1, \(chromeTime(recent)))") }
        chromeInserts.append("INSERT INTO visits (id, url, visit_time) VALUES (20, 2, \(chromeTime(recent)))")
        chromeInserts.append("INSERT INTO visits (id, url, visit_time) VALUES (21, 3, \(chromeTime(old)))")
        try makeDB(chrome, schema: "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT); CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER);", inserts: chromeInserts)

        let firefox = dir.appendingPathComponent("places.sqlite")
        var ffInserts = ["INSERT INTO moz_places (id, url) VALUES (1, 'https://www.youtube.com/watch?v=1')"]
        for i in 0..<3 { ffInserts.append("INSERT INTO moz_historyvisits (id, place_id, visit_date) VALUES (\(i + 1), 1, \(firefoxTime(recent)))") }
        try makeDB(firefox, schema: "CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT); CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER, visit_date INTEGER);", inserts: ffInserts)

        let indexer = HistoryIndexer(cacheDir: dir.appendingPathComponent("cache"))
        let index = try indexer.build(sources: [
            HistorySource(target: "work", kind: .chrome, dbPath: chrome),
            HistorySource(target: "ads", kind: .firefox, dbPath: firefox),
        ], now: now)

        #expect(index.hosts["my.hosting.com"] == ["work": 6])
        #expect(index.hosts["old.example"] == nil)
        #expect(index.fileTarget(docID) == "work")
        #expect(index.hosts["youtube.com"] == ["ads": 3])
        #expect(index.hostVerdict("youtube.com") == .mixed(counts: ["ads": 3]))
        #expect(index.hostVerdict("my.hosting.com") == .confident("work", share: 1.0, total: 6))
    }

    @Test func buildsFromSafari() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let recent = now.addingTimeInterval(-86_400).timeIntervalSinceReferenceDate
        let old = now.addingTimeInterval(-100 * 86_400).timeIntervalSinceReferenceDate
        let db = dir.appendingPathComponent("History.db")
        var inserts = [
            "INSERT INTO history_items (id, url) VALUES (1, 'https://www.apple.com/mac/')",
            "INSERT INTO history_items (id, url) VALUES (2, 'https://old.example/')",
        ]
        for i in 0..<5 { inserts.append("INSERT INTO history_visits (id, history_item, visit_time) VALUES (\(i + 1), 1, \(recent))") }
        inserts.append("INSERT INTO history_visits (id, history_item, visit_time) VALUES (10, 2, \(old))")
        try makeDB(db, schema: "CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT); CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL);", inserts: inserts)
        let index = try HistoryIndexer(cacheDir: dir.appendingPathComponent("cache")).build(sources: [HistorySource(target: "safari", kind: .safari, dbPath: db)], now: now)
        #expect(index.hosts["apple.com"] == ["safari": 5])
        #expect(index.hosts["old.example"] == nil)
    }

    @Test func missingSourceIsSkipped() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let indexer = HistoryIndexer(cacheDir: dir)
        let index = try indexer.build(sources: [HistorySource(target: "work", kind: .chrome, dbPath: dir.appendingPathComponent("nope"))], now: Date())
        #expect(index.hosts.isEmpty)
    }

    @Test func displayNamesParses() {
        let json = #"{"profile":{"info_cache":{"Default":{"name":"Me"},"Profile 1":{"name":"Work"}}}}"#
        let names = ChromeProfiles.displayNames(localStateData: Data(json.utf8))
        #expect(names == ["Default": "Me", "Profile 1": "Work"])
        #expect(ChromeProfiles.displayNames(localStateData: Data("x".utf8)).isEmpty)
    }
}

@Suite struct FirefoxProfilesTests {
    let base = URL(fileURLWithPath: "/ff")

    @Test func installSectionWins() {
        let ini = "[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/aaa.default\nDefault=1\n\n[Install123]\nDefault=Profiles/bbb.default-release\nLocked=1\n"
        #expect(FirefoxProfiles.defaultProfilePath(iniText: ini, baseDir: base)?.path == "/ff/Profiles/bbb.default-release")
    }

    @Test func defaultProfileFlag() {
        let ini = "[Profile1]\nPath=Profiles/x\nIsRelative=1\n[Profile0]\nPath=Profiles/y\nIsRelative=1\nDefault=1\n"
        #expect(FirefoxProfiles.defaultProfilePath(iniText: ini, baseDir: base)?.path == "/ff/Profiles/y")
    }

    @Test func emptyIni() {
        #expect(FirefoxProfiles.defaultProfilePath(iniText: "", baseDir: base) == nil)
    }
}

@Suite struct ProfileCheckTests {
    @Test func renameWarnsButKeepsRouting() {
        let problems = ProfileCheck.problems(destinations: RulesConfig.fixture.destinations, names: ["Default": "Me", "Profile 1": "Renamed"])
        #expect(problems["work"]?.blocksRouting == false)
        #expect(problems["personal"] == nil)
    }

    @Test func missingFolderBlocksRouting() {
        let problems = ProfileCheck.problems(destinations: RulesConfig.fixture.destinations, names: ["Default": "Me"])
        #expect(problems["work"]?.blocksRouting == true)
    }

    @Test func matchingNamesHaveNoProblems() {
        let problems = ProfileCheck.problems(destinations: RulesConfig.fixture.destinations, names: ["Default": "Me", "Profile 1": "Work"])
        #expect(problems.isEmpty)
    }
}
