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

public struct BrowserLinks: Codable, Equatable, Sendable {
    public var chrome: [String: DestinationID] = [:]

    public init() {}

    public static let fileName = "agent-browsers.json"

    public func device(for destination: DestinationID) -> String? {
        chrome.filter { $0.value == destination }.keys.sorted().first
    }

    public mutating func remember(deviceID: String, destination: DestinationID) {
        chrome = chrome.filter { $0.value != destination && $0.key != deviceID }
        chrome[deviceID] = destination
    }

    public static func load(from dir: URL = DetourFiles.supportDir()) -> BrowserLinks {
        (try? JSONDecoder().decode(BrowserLinks.self, from: Data(contentsOf: dir.appendingPathComponent(fileName)))) ?? BrowserLinks()
    }

    public func save(to dir: URL = DetourFiles.supportDir()) throws {
        try ConfigLoader.save(self, to: dir.appendingPathComponent(Self.fileName))
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
    public var chromeConnection: String?
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
    public static func answer(for link: String, engine: RoutingEngine, links: BrowserLinks = BrowserLinks()) throws -> AgentAnswer {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { throw AgentError.notAWebLink }
        let prepared = engine.rules.prepare(url)
        let decision = engine.decide(LinkContext(url: prepared))
        let target = engine.rules.destination(decision.target)
        return AgentAnswer(url: prepared.absoluteString, destination: decision.target, name: target?.name ?? decision.target,
                           browser: target.map(browserName) ?? "your default browser", profile: target?.profileName,
                           privateWindow: target?.privateWindow ?? false, askUser: decision.askUser, reason: decision.reason,
                           chromeConnection: links.device(for: decision.target))
    }

    public static func describe(_ answer: AgentAnswer) -> String {
        var place = "\(answer.name) (\(answer.browser)"
        if let profile = answer.profile { place += ", profile \"\(profile)\"" }
        if answer.privateWindow { place += ", private window" }
        place += ")"
        let head = answer.askUser ? "Detour would ask the user, best guess \(place)" : "Opens in \(place)"
        let connection = answer.chromeConnection.map { "Claude in Chrome connection: \($0)." }
            ?? "There is no Claude in Chrome connection remembered for \(answer.name) yet."
        return "\(head): \(answer.reason). URL: \(answer.url). \(connection)"
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
    static let supportedVersions: Set<String> = ["2025-06-18", "2025-11-25"]
    public static let instructions = """
    Detour is the user's link router: it knows which browser and which browser profile (for example a work or a personal Chrome profile) the user opens each website in.

    Before you visit a URL with a browser automation tool that controls one specific browser or profile, such as Claude in Chrome, call which_browser with that URL. It returns the Detour destination name, the browser and the profile name.

    With Claude in Chrome: which_browser also returns chromeConnection, the deviceId of the Claude in Chrome connection the user paired with that destination. Connection names like "Browser 1" mean nothing, so always go by deviceId.
    - If chromeConnection is the browser in use, continue.
    - If chromeConnection is another connected browser, tell the user this link belongs to that profile before you continue, and offer to switch to it (select_browser with that deviceId).
    - When you ask the user which connected browser to use, list the chromeConnection first and mark it as recommended.
    - If chromeConnection is missing or not in list_connected_browsers, find out which connection is that profile. Connection names don't say which Chrome window they control and the user can't tell them apart either, so never guess and don't offer "the one used last" as a hint. For each connected browser Detour doesn't know yet, one at a time: select_browser with its deviceId, open a new tab with tabs_create_mcp, then ask the user which window or profile the tab just appeared in. Call remember_browser with that deviceId and the destination the user names, so Detour knows next time. Close the tabs you opened for this afterwards.

    If which_browser says Detour would ask, the site is used in several profiles: check with the user. If the destination is not a Chromium browser (for example Firefox), say so instead of using Claude in Chrome.

    To just open a link for the user to look at, call open_link: it opens in the right browser and profile, exactly like a click.
    """

    let engine: () throws -> RoutingEngine
    let open: (URL) -> Bool
    let loadLinks: () -> BrowserLinks
    let saveLinks: (BrowserLinks) throws -> Void

    public init(engine: @escaping () throws -> RoutingEngine, open: @escaping (URL) -> Bool,
                loadLinks: @escaping () -> BrowserLinks = { BrowserLinks() }, saveLinks: @escaping (BrowserLinks) throws -> Void = { _ in }) {
        self.engine = engine
        self.open = open
        self.loadLinks = loadLinks
        self.saveLinks = saveLinks
    }

    public func handle(line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed]) else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let message = parsed as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil }
        if message["result"] != nil || message["error"] != nil { return nil }
        guard let method = message["method"] as? String else {
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid request"]])
        }
        let params = message["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": (params["protocolVersion"] as? String).flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "detour", "title": "Detour", "version": Self.version],
                "instructions": Self.instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools]
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
                return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool: \(name)"]])
            }
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
                let answer = try AgentBridge.answer(for: arguments["url"] as? String ?? "", engine: engine(), links: loadLinks())
                return content(AgentBridge.describe(answer), structured: answer)
            case "open_link":
                let answer = try AgentBridge.answer(for: arguments["url"] as? String ?? "", engine: engine(), links: loadLinks())
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
            case "remember_browser":
                let rules = try engine().rules
                let wanted = (arguments["destination"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                let device = (arguments["device_id"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !device.isEmpty else { return failure("Pass the deviceId from list_connected_browsers as device_id.") }
                guard let target = rules.destinations.first(where: {
                    $0.id.caseInsensitiveCompare(wanted) == .orderedSame || $0.name.caseInsensitiveCompare(wanted) == .orderedSame
                }) else {
                    return failure("Detour has no destination \"\(wanted)\". Use one of: \(rules.destinations.map(\.name).joined(separator: ", ")).")
                }
                var links = loadLinks()
                links.remember(deviceID: device, destination: target.id)
                try saveLinks(links)
                return content("Remembered: Claude in Chrome connection \(device) is \(target.name).", structured: ["destination": target.id, "chromeConnection": device])
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
        ["name": "remember_browser", "title": "Remember a Claude in Chrome connection",
         "description": "Saves which Claude in Chrome connection (deviceId from list_connected_browsers) is a Detour destination, so which_browser can return it next time. Call it after the user tells you which connection is that profile.",
         "inputSchema": [
            "type": "object",
            "properties": [
                "device_id": ["type": "string", "description": "deviceId from list_connected_browsers"],
                "destination": ["type": "string", "description": "Detour destination name or id, as returned by which_browser"],
            ],
            "required": ["device_id", "destination"],
         ], "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false]],
    ] }

    private func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
