import AppKit
import DetourCore

enum DestinationOpener {
    struct OpenError: Error {}

    @MainActor
    static func open(_ url: URL, destination: Destination) async throws {
        let appURL = URL(fileURLWithPath: destination.appPath)
        guard FileManager.default.fileExists(atPath: appURL.path) else { throw OpenError() }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        if let dir = destination.profileDir {
            let arguments = ["--profile-directory=\(dir)", url.absoluteString]
            if isRunning(appURL) {
                try launchBinary(appURL: appURL, arguments: arguments)
            } else {
                config.arguments = arguments
                config.createsNewApplicationInstance = true
                do {
                    _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
                } catch {
                    try launchBinary(appURL: appURL, arguments: arguments)
                }
            }
        } else {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
        }
    }

    @MainActor
    static func openAnywhere(_ url: URL) async -> Bool {
        let routers: Set<String> = [BrowserDiscovery.ownBundleID, "nl.ten50.linkrouter", "com.choosyosx.choosy", "com.sindresorhus.Velja", "se.johnste.finicky"]
        let browsers = NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "https://example.com")!)
            .filter { url in !routers.contains(Bundle(url: url)?.bundleIdentifier ?? "") }
        guard let browser = browsers.first(where: { $0.lastPathComponent == "Safari.app" }) ?? browsers.first else { return false }
        return (try? await NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())) != nil
    }

    private static func isRunning(_ appURL: URL) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.standardizedFileURL == appURL.standardizedFileURL }
    }

    private static func launchBinary(appURL: URL, arguments: [String]) throws {
        guard let bundle = Bundle(url: appURL), let exe = bundle.executableURL else { throw OpenError() }
        let process = Process()
        process.executableURL = exe
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
