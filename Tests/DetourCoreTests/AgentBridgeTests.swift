import Foundation
import Testing
@testable import DetourCore

@Suite struct AgentBridgeTests {
    var engine: RoutingEngine {
        var rules = RulesConfig.fixture
        rules.rewrites = [RewriteRule(from: "reddit.com", to: "old.reddit.com")]
        return RoutingEngine(rules: rules)
    }

    @Test func ruleMatchGivesBrowserAndProfile() throws {
        let answer = try AgentBridge.answer(for: "https://acme-corp.atlassian.net/browse/X-1", engine: engine)
        #expect(answer.destination == "work")
        #expect(answer.name == "Work")
        #expect(answer.browser == "Google Chrome")
        #expect(answer.profile == "Work")
        #expect(!answer.askUser)
        #expect(answer.reason.hasPrefix("matches your rule"))
    }

    @Test func answerUsesRewrittenURL() throws {
        let answer = try AgentBridge.answer(for: "https://www.reddit.com/r/macapps", engine: engine)
        #expect(answer.url == "https://old.reddit.com/r/macapps")
        #expect(answer.destination == "personal")
    }

    @Test func ambiguousHostAsks() throws {
        let answer = try AgentBridge.answer(for: "https://docs.google.com/document/d/x", engine: engine)
        #expect(answer.askUser)
        #expect(AgentBridge.describe(answer).hasPrefix("Detour would ask"))
    }

    @Test func noAccountEmailInOutput() throws {
        let answer = try AgentBridge.answer(for: "https://acme-corp.atlassian.net/", engine: engine)
        let json = String(decoding: try JSONEncoder().encode(answer), as: UTF8.self)
        #expect(!json.contains("me@acme.com"))
    }

    @Test func nonWebLinkThrows() {
        #expect(throws: AgentError.notAWebLink) { try AgentBridge.answer(for: "ftp://x", engine: engine) }
        #expect(throws: AgentError.notAWebLink) { try AgentBridge.answer(for: "not a url", engine: engine) }
    }

    @Test func browsersListsEveryDestination() {
        let list = AgentBridge.browsers(engine.rules)
        #expect(list.map(\.name) == ["Work", "Ad-free", "Personal"])
        #expect(list[1].browser == "Firefox")
        #expect(list[1].profile == nil)
        #expect(list[2].isDefault)
    }

    @Test func missingSettingsThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: AgentError.noSettings) { try DetourFiles.loadEngine(from: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ConfigLoader.save(RulesConfig.fixture, to: dir.appendingPathComponent("rules.json"))
        #expect(try DetourFiles.loadEngine(from: dir).rules.destinations.count == 3)
    }

    @Test func supportDirHonoursOverride() {
        #expect(DetourFiles.supportDir(environment: ["DETOUR_CONFIG_DIR": "/tmp/x"]).path == "/tmp/x")
        #expect(DetourFiles.supportDir(environment: [:]).path.hasSuffix("Library/Application Support/Detour"))
    }
}

@Suite struct MCPServerTests {
    final class Opened: @unchecked Sendable { var urls: [URL] = [] }

    func server(_ opened: Opened = Opened(), settings: Bool = true) -> MCPServer {
        MCPServer(engine: {
            guard settings else { throw AgentError.noSettings }
            return RoutingEngine(rules: .fixture)
        }, open: { opened.urls.append($0); return true })
    }

    func call(_ server: MCPServer, _ json: String) throws -> [String: Any] {
        let line = try #require(server.handle(line: json))
        return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func text(_ response: [String: Any]) -> String {
        let result = response["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    @Test func initializeSendsInstructions() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        let result = try #require(r["result"] as? [String: Any])
        #expect((result["instructions"] as? String)?.contains("list_connected_browsers") == true)
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect(r["id"] as? Int == 1)
    }

    @Test func listsThreeTools() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":"a","method":"tools/list"}"#)
        let tools = try #require((r["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["which_browser", "open_link", "list_browsers"])
        #expect(r["id"] as? String == "a")
    }

    @Test func whichBrowserAnswers() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"which_browser","arguments":{"url":"https://youtube.com/watch?v=1"}}}"#)
        #expect(text(r).contains("Ad-free"))
        let structured = (r["result"] as? [String: Any])?["structuredContent"] as? [String: Any]
        #expect(structured?["destination"] as? String == "ads")
    }

    @Test func badURLIsToolError() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"which_browser","arguments":{"url":"mailto:a@b.c"}}}"#)
        #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
    }

    @Test func missingSettingsIsToolError() throws {
        let r = try call(server(settings: false), #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_browsers","arguments":{}}}"#)
        #expect((r["result"] as? [String: Any])?["isError"] as? Bool == true)
        #expect(text(r).contains("no settings"))
    }

    @Test func openLinkHandsURLToDetour() throws {
        let opened = Opened()
        let r = try call(server(opened), #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"open_link","arguments":{"url":"https://reddit.com/"}}}"#)
        #expect(opened.urls == [URL(string: "https://reddit.com/")!])
        #expect(text(r).contains("Personal"))
    }

    @Test func unknownMethodAndNotifications() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#)
        #expect((r["error"] as? [String: Any])?["code"] as? Int == -32601)
        #expect(server().handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        #expect(server().handle(line: "   ") == nil)
    }

    @Test func garbageIsParseError() throws {
        let r = try call(server(), "{nope")
        #expect((r["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test func unsupportedProtocolVersionGetsOurs() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#)
        #expect((r["result"] as? [String: Any])?["protocolVersion"] as? String == MCPServer.protocolVersion)
    }

    @Test func unknownToolIsInvalidParams() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#)
        #expect((r["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test func invalidRequests() throws {
        let array = try call(server(), "[1,2]")
        #expect((array["error"] as? [String: Any])?["code"] as? Int == -32600)
        let noMethod = try call(server(), #"{"jsonrpc":"2.0","id":7}"#)
        #expect((noMethod["error"] as? [String: Any])?["code"] as? Int == -32600)
        #expect(server().handle(line: #"{"jsonrpc":"2.0","id":7,"result":{}}"#) == nil)
    }

    @Test func pingAnswers() throws {
        let r = try call(server(), #"{"jsonrpc":"2.0","id":9,"method":"ping"}"#)
        #expect(r["result"] is [String: Any])
    }
}
