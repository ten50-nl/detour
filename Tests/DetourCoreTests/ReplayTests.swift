import Foundation
import Testing
@testable import DetourCore

struct ReplayRow: Decodable {
    let host: String
    let srcApp: String
    let srcTitle: String
    let expected: DestinationID
}

private let replayFixture = ProcessInfo.processInfo.environment["DETOUR_REPLAY_FIXTURE"]
private let replayRules = ProcessInfo.processInfo.environment["DETOUR_REPLAY_RULES"]

@Suite struct ReplayTests {
    @Test(.enabled(if: replayFixture != nil && replayRules != nil, "set DETOUR_REPLAY_FIXTURE and DETOUR_REPLAY_RULES to run"))
    func replayAgreement() throws {
        let url = URL(fileURLWithPath: try #require(replayFixture))
        let rows = try JSONDecoder().decode([ReplayRow].self, from: Data(contentsOf: url))
        try #require(rows.count > 300)
        let (rules, error) = ConfigLoader.loadRules(from: URL(fileURLWithPath: try #require(replayRules)), fallback: .empty)
        try #require(error == nil)
        let engine = RoutingEngine(rules: rules)
        var agree = 0
        var asks = 0
        var byRule = 0
        var misses: [String] = []
        for row in rows {
            let d = engine.decide(LinkContext(url: URL(string: "https://\(row.host)/")!, sourceApp: row.srcApp, sourceWindowTitle: row.srcTitle))
            if d.askUser { asks += 1; misses.append("ASK  \(row.host) from \(row.srcApp), you chose \(row.expected)") }
            else if d.target == row.expected { agree += 1 }
            else if d.stage == .rule { agree += 1; byRule += 1 }
            else { misses.append("MISS \(row.host) -> \(d.target) (\(d.reason)), you chose \(row.expected)") }
        }
        let total = Double(rows.count)
        print("replay: \(agree)/\(rows.count) agree (\(byRule) changed on purpose by your rules), \(asks) asks")
        misses.forEach { print("  " + $0) }
        #expect(Double(agree) / total >= 0.92)
        #expect(Double(asks) / total <= 0.08)
    }
}
