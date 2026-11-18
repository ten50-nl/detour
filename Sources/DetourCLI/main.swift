import DetourCore
import Foundation

let usage = """
Usage:
  detour which <url> [--json]   Show the browser and profile Detour picks for a link
  detour open <url>             Open a link with Detour, like clicking it
  detour browsers [--json]      List your Detour destinations
  detour mcp                    Run as an MCP server for AI agents (stdio)

Add it to Claude Code:  claude mcp add detour -- \(CommandLine.arguments[0]) mcp
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func openWithDetour(_ url: URL) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", "nl.ten50.detour", url.absoluteString]
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

func printJSON<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: (try? encoder.encode(value)) ?? Data(), as: UTF8.self))
}

var args = Array(CommandLine.arguments.dropFirst())
let json = args.contains("--json")
args.removeAll { $0 == "--json" }

switch args.first {
case "which":
    guard args.count == 2 else { fail(usage, code: 64) }
    do {
        let answer = try AgentBridge.answer(for: args[1], engine: DetourFiles.loadEngine())
        json ? printJSON(answer) : print(AgentBridge.describe(answer))
    } catch { fail(error.localizedDescription) }
case "open":
    guard args.count == 2 else { fail(usage, code: 64) }
    let link = args[1].trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { fail(AgentError.notAWebLink.localizedDescription) }
    guard openWithDetour(url) else { fail("Detour couldn't open the link. Is Detour installed?") }
case "browsers":
    do {
        let list = AgentBridge.browsers(try DetourFiles.loadEngine().rules)
        if json { printJSON(list) } else {
            for item in list {
                print("\(item.name): \(item.browser)\(item.profile.map { ", profile \"\($0)\"" } ?? "")\(item.isDefault ? " (default)" : "")")
            }
        }
    } catch { fail(error.localizedDescription) }
case "mcp":
    let server = MCPServer(engine: { try DetourFiles.loadEngine() }, open: openWithDetour)
    while let line = readLine(strippingNewline: true) {
        if let reply = server.handle(line: line) {
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }
case "-h", "--help", "help", nil:
    print(usage)
default:
    fail(usage, code: 64)
}
