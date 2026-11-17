import AppKit
import OSLog
import DetourCore

let routingLog = Logger(subsystem: "nl.ten50.detour", category: "routing")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    var menuBar: MenuBarController?
    var settings: SettingsWindowController?
    var onboarding: OnboardingWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        SourceContext.startTracking()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.requestPermission()
        settings = SettingsWindowController(state: state)
        onboarding = OnboardingWindowController(state: state)
        menuBar = MenuBarController(state: state, openSettings: { [weak self] in self?.settings?.show() })
        menuBar?.openOnboarding = { [weak self] in self?.onboarding?.show() }
        state.presentPicker = { [weak self] url, decision, completion in
            guard let state = self?.state else { return }
            let names = state.rules.displayNames()
            let shown = state.destinations.map { dest -> Destination in var d = dest; d.name = names[dest.id] ?? dest.name; return d }
            PickerPanel.show(url: url, decision: decision, destinations: shown, completion: completion)
        }
        state.start()
        if BrowserScanner.isDemo, let raw = ProcessInfo.processInfo.environment["DETOUR_PICKER_URL"], let url = URL(string: raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.state.handle(LinkContext(url: url, sourceApp: "Mail"))
            }
            return
        }
        if state.rulesFileBroken {
            Notifier.rulesBroken()
            settings?.show()
        } else if !state.onboardingDone || !state.hasConfig {
            onboarding?.show()
        } else if CommandLine.arguments.contains("--settings") {
            settings?.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !state.onboardingDone { onboarding?.show() } else { settings?.show() }
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                state.open(url, in: state.rules.defaultDestination, remember: false)
            } else {
                route(url, senderPID: nil)
            }
        }
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        let force = NSEvent.modifierFlags.contains(.option)
        let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? ""
        guard let url = LinkParser.parse(raw) else {
            routingLog.error("could not read link \(raw, privacy: .private)")
            return
        }
        route(url, senderPID: pid, force: force)
    }

    private func route(_ url: URL, senderPID: pid_t?, force: Bool = NSEvent.modifierFlags.contains(.option)) {
        let source = SourceContext.capture(senderPID: senderPID)
        routingLog.info("link \(url.host() ?? "-", privacy: .public) app=\(source.app ?? "-", privacy: .public)")
        state.handle(LinkContext(url: url, sourceApp: source.app, forcePicker: force, titleProvider: source.title))
    }
}
