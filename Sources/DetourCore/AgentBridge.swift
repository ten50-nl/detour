import Foundation

public enum AgentError: LocalizedError, Equatable {
    case notAWebLink, noSettings

    public var errorDescription: String? {
        switch self {
        case .notAWebLink: "That isn't a web link. Pass a full http or https URL."
        case .noSettings: "Detour has no settings yet. Open Detour once and finish setup."
        }
    }
}

public enum DetourFiles {
    public static func supportDir(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let dir = environment["DETOUR_CONFIG_DIR"] { return URL(fileURLWithPath: dir) }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Application Support/Detour")
    }

    public static func loadEngine(from dir: URL = supportDir()) throws -> RoutingEngine {
        let rulesURL = dir.appendingPathComponent("rules.json")
        guard FileManager.default.fileExists(atPath: rulesURL.path) else { throw AgentError.noSettings }
        let (rules, error) = ConfigLoader.loadRules(from: rulesURL, fallback: .empty)
        if let error { throw error }
        guard !rules.destinations.isEmpty else { throw AgentError.noSettings }
        let learned = (try? JSONDecoder().decode(LearnedStore.self, from: Data(contentsOf: dir.appendingPathComponent("learned.json")))) ?? LearnedStore()
        let history = try? JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: dir.appendingPathComponent("history-index.json")))
        return RoutingEngine(rules: rules, learned: learned, history: history)
    }
}

public struct AgentAnswer: Codable, Equatable, Sendable {
    public var url: String
    public var destination: DestinationID
    public var name: String
    public var browser: String
    public var profile: String?
    public var privateWindow: Bool
    public var askUser: Bool
    public var reason: String
}

public struct AgentBrowserInfo: Codable, Equatable, Sendable {
    public var destination: DestinationID
    public var name: String
    public var browser: String
    public var profile: String?
    public var privateWindow: Bool
    public var isDefault: Bool
}

public enum AgentBridge {
    public static func answer(for link: String, engine: RoutingEngine) throws -> AgentAnswer {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { throw AgentError.notAWebLink }
        let prepared = engine.rules.prepare(url)
        let decision = engine.decide(LinkContext(url: prepared))
        let target = engine.rules.destination(decision.target)
        return AgentAnswer(url: prepared.absoluteString, destination: decision.target, name: target?.name ?? decision.target,
                           browser: target.map(browserName) ?? "your default browser", profile: target?.profileName,
                           privateWindow: target?.privateWindow ?? false, askUser: decision.askUser, reason: decision.reason)
    }

    public static func describe(_ answer: AgentAnswer) -> String {
        var place = "\(answer.name) (\(answer.browser)"
        if let profile = answer.profile { place += ", profile \"\(profile)\"" }
        if answer.privateWindow { place += ", private window" }
        place += ")"
        let head = answer.askUser ? "Detour would ask the user, best guess \(place)" : "Opens in \(place)"
        return "\(head): \(answer.reason). URL: \(answer.url)"
    }

    public static func browsers(_ rules: RulesConfig) -> [AgentBrowserInfo] {
        rules.destinations.map {
            AgentBrowserInfo(destination: $0.id, name: $0.name, browser: browserName($0), profile: $0.profileName,
                             privateWindow: $0.privateWindow, isDefault: $0.id == rules.defaultDestination)
        }
    }

    static func browserName(_ destination: Destination) -> String {
        URL(fileURLWithPath: destination.appPath).deletingPathExtension().lastPathComponent
    }
}

public struct MCPServer {
    public static let protocolVersion = "2025-06-18"
    public static let instructions = """
    Detour is the user's link router: it knows which browser and which browser profile (for example a work or a personal Chrome profile) the user opens each website in.

    Before you visit a URL with a browser automation tool that controls one specific browser or profile, such as Claude in Chrome, call which_browser with that URL. It returns the Detour destination name, the browser and the profile name.

    With Claude in Chrome, compare that destination name and profile name with the names from list_connected_browsers. If the browser in use doesn't match, tell the user which profile Detour expects before you continue in it. When you ask the user which connected browser to use, list the Detour match first and mark it as recommended. If no connected browser matches, suggest the user reconnects that profile with switch_browser and names it after the Detour destination.

    If which_browser says Detour would ask, the site is used in several profiles: check with the user. If the destination is not a Chromium browser (for example Firefox), say so instead of using Claude in Chrome.

    To just open a link for the user to look at, call open_link: it opens in the right browser and profile, exactly like a click.
    """

    let engine: () throws -> RoutingEngine
    let open: (URL) -> Bool

    public init(engine: @escaping () throws -> RoutingEngine, open: @escaping (URL) -> Bool) {
        self.engine = engine
        self.open = open
    }

    public func handle(line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": (params["protocolVersion"] as? String) ?? Self.protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "detour", "title": "Detour", "version": Self.version],
                "instructions": Self.instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            result = call(name: params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    public static var version: String {
        if let own = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return own }
        let contents = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        guard let plist = contents?.appendingPathComponent("Info.plist"),
              let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String else { return "dev" }
        return version
    }

    private func call(name: String, arguments: [String: Any]) -> [String: Any] {
        do {
            switch name {
            case "which_browser":
                let answer = try AgentBridge.answer(for: arguments["url"] as? String ?? "", engine: engine())
                return content(AgentBridge.describe(answer), structured: answer)
            case "open_link":
                let answer = try AgentBridge.answer(for: arguments["url"] as? String ?? "", engine: engine())
                let link = arguments["url"] as? String ?? ""
                guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)), open(url) else {
                    return failure("Detour couldn't open the link. Is Detour installed?")
                }
                return content("Opened with Detour. \(AgentBridge.describe(answer))", structured: answer)
            case "list_browsers":
                let list = AgentBridge.browsers(try engine().rules)
                let lines = list.map { item in
                    var line = "\(item.name): \(item.browser)"
                    if let profile = item.profile { line += ", profile \"\(profile)\"" }
                    if item.privateWindow { line += ", private window" }
                    if item.isDefault { line += " (default)" }
                    return line
                }
                return content(lines.joined(separator: "\n"), structured: ["browsers": list])
            default:
                return failure("Unknown tool \(name)")
            }
        } catch {
            return failure(error.localizedDescription)
        }
    }

    private func content<T: Encodable>(_ text: String, structured: T) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if let data = try? JSONEncoder().encode(structured), let object = try? JSONSerialization.jsonObject(with: data) {
            result["structuredContent"] = object
        }
        return result
    }

    private func failure(_ text: String) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": true]
    }

    private static var urlInput: [String: Any] { [
        "type": "object",
        "properties": ["url": ["type": "string", "description": "Full http or https URL"]],
        "required": ["url"],
    ] }

    static var tools: [[String: Any]] { [
        ["name": "which_browser", "title": "Which browser and profile",
         "description": "Tells which browser and profile the user opens this URL in, according to their Detour rules and history, without opening it. Call it before browsing a URL with a tool that controls a specific browser profile.",
         "inputSchema": urlInput, "annotations": ["readOnlyHint": true, "openWorldHint": false]],
        ["name": "open_link", "title": "Open link with Detour",
         "description": "Opens the URL for the user in the right browser and profile, exactly like clicking it. Use this instead of opening links yourself when the user just wants to see a page.",
         "inputSchema": urlInput, "annotations": ["readOnlyHint": false, "destructiveHint": false, "openWorldHint": true]],
        ["name": "list_browsers", "title": "List Detour destinations",
         "description": "Lists the user's Detour destinations: name, browser and profile, and which one is the default.",
         "inputSchema": ["type": "object", "properties": [String: Any]()], "annotations": ["readOnlyHint": true, "openWorldHint": false]],
    ] }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
