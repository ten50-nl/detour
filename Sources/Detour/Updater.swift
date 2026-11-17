import AppKit
import DetourCore

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let enabledKey = "automaticUpdateChecks"
    static let lastCheckKey = "lastUpdateCheck"
    static let notifiedKey = "notifiedUpdateVersion"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(AvailableUpdate)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    private var timer: Timer?

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { checkIfDue() }
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var available: AvailableUpdate? {
        if case .available(let update) = status { return update }
        return nil
    }

    var isHomebrewInstall: Bool {
        ["/opt/homebrew/Caskroom/detour", "/usr/local/Caskroom/detour"].contains { FileManager.default.fileExists(atPath: $0) }
    }

    func selfTestIfRequested() {
        guard Paths.isIsolated, ProcessInfo.processInfo.environment["DETOUR_UPDATE_SELFTEST"] != nil else { return }
        check(userInitiated: true)
        Task {
            for _ in 0..<40 {
                try? await Task.sleep(for: .milliseconds(500))
                if available != nil { install(); return }
                if case .failed(let message) = status { NSLog("detour-update-test: \(message)"); return }
                if case .upToDate = status { NSLog("detour-update-test: up to date"); return }
            }
        }
    }

    func start() {
        selfTestIfRequested()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.checkIfDue() }
    }

    func checkIfDue() {
        guard enabled, !Paths.isIsolated, !BrowserScanner.isDemo else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard UpdateCheck.isDue(lastCheck: last, now: Date()) else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard status != .checking else { return }
        status = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Links.repoSlug)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Detour/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let version = currentVersion
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub answered with an error") }
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                if let update = UpdateCheck.evaluate(currentVersion: version, releaseJSON: data) {
                    status = .available(update)
                    notifyOnce(update)
                } else {
                    status = .upToDate(Date())
                }
            } catch {
                status = userInitiated ? .failed("Could not check for updates: \(error.localizedDescription)") : .idle
            }
        }
    }

    private func notifyOnce(_ update: AvailableUpdate) {
        guard UserDefaults.standard.string(forKey: Self.notifiedKey) != update.version else { return }
        UserDefaults.standard.set(update.version, forKey: Self.notifiedKey)
        Notifier.updateAvailable(version: update.version, homebrew: isHomebrewInstall)
    }

    func install() {
        guard let update = available else { return }
        if isHomebrewInstall {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew upgrade --cask detour", forType: .string)
            status = .failed("Detour was installed with Homebrew. Run brew upgrade --cask detour in Terminal (copied to your clipboard).")
            return
        }
        status = .installing("Downloading Detour \(update.version)…")
        let target = Bundle.main.bundleURL
        Task.detached(priority: .userInitiated) {
            do {
                let (file, _) = try await URLSession.shared.download(from: update.downloadURL)
                await MainActor.run { Updater.shared.status = .installing("Checking the signature…") }
                try Self.replace(app: target, withAppIn: file)
                await MainActor.run { Updater.shared.relaunch(target) }
            } catch {
                await MainActor.run { Updater.shared.status = .failed("Update failed: \(error.localizedDescription). Your current version keeps working.") }
            }
        }
    }

    nonisolated private static func replace(app target: URL, withAppIn dmg: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("detour-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mount")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: work)
        }
        _ = try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
        let newApp = mount.appendingPathComponent("Detour.app")
        guard fm.fileExists(atPath: newApp.path) else { throw UpdateError("The download doesn't contain Detour.app") }

        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        let newTeam = UpdateCheck.teamIdentifier(fromCodesignOutput: try run("/usr/bin/codesign", ["-dv", newApp.path]))
        let ownTeam = UpdateCheck.teamIdentifier(fromCodesignOutput: try run("/usr/bin/codesign", ["-dv", target.path]))
        guard let newTeam, newTeam == ownTeam else { throw UpdateError("The download isn't signed by the same developer") }
        _ = try run("/usr/sbin/spctl", ["--assess", "--type", "execute", newApp.path])

        let staged = target.deletingLastPathComponent().appendingPathComponent(".Detour-update.app")
        try? fm.removeItem(at: staged)
        _ = try run("/usr/bin/ditto", [newApp.path, staged.path])
        var trashed: NSURL?
        try fm.trashItem(at: target, resultingItemURL: &trashed)
        do {
            try fm.moveItem(at: staged, to: target)
        } catch {
            if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: target) }
            throw error
        }
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed") }
        return output
    }

    private func relaunch(_ app: URL) {
        if Paths.isIsolated {
            status = .installing("Installed \(app.path). Restart skipped in test mode.")
            NSLog("detour-update-test: installed")
            return
        }
        status = .installing("Restarting…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
