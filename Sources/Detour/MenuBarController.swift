import AppKit
import DetourCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let showIconKey = "showMenuBarIcon"

    private let state: AppState
    private let openSettings: () -> Void
    var openOnboarding: () -> Void = {}
    private var item: NSStatusItem?

    init(state: AppState, openSettings: @escaping () -> Void) {
        self.state = state
        self.openSettings = openSettings
        super.init()
        UserDefaults.standard.register(defaults: [Self.showIconKey: true])
        refreshVisibility()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }
    }

    private func refreshVisibility() {
        let show = UserDefaults.standard.bool(forKey: Self.showIconKey)
        if show, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = DetourGlyph.menuBarImage()
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            self.item = item
        } else if !show, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let update = Updater.shared.available {
            menu.addItem(action("Update to Detour \(update.version)…", #selector(installUpdate)))
            menu.addItem(.separator())
        }
        if state.recent.isEmpty {
            menu.addItem(disabled("No links yet"))
        } else {
            menu.addItem(disabled("Recent links"))
            for link in state.recent {
                menu.addItem(recentItem(link))
            }
        }
        menu.addItem(.separator())
        if case .noAccess = state.historyStatus {
            menu.addItem(disabled("History not used: needs Full Disk Access"))
        }
        menu.addItem(action("Rebuild history index", #selector(rebuild)))
        menu.addItem(action("Set up again…", #selector(setup)))
        menu.addItem(action("Check for updates", #selector(checkUpdates)))
        menu.addItem(action("Settings…", #selector(settings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Quit Detour", #selector(quit), key: "q"))
    }

    private func recentItem(_ link: RecentLink) -> NSMenuItem {
        let host = normalizedHost(link.url) ?? link.url.absoluteString
        let where_ = link.opened.map { state.label($0) } ?? "not opened"
        let item = NSMenuItem(title: "\(host)  →  \(where_)", action: nil, keyEquivalent: "")
        item.toolTip = "\(link.url.absoluteString)\n\(link.decision.reason)\(link.sourceApp.map { "\nfrom \($0)" } ?? "")"
        let sub = NSMenu()
        for dest in state.destinations {
            let open = NSMenuItem(title: "Open in \(state.label(dest.id))", action: #selector(reopen(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = ReopenRequest(id: link.id, url: link.url, target: dest.id)
            if link.opened == dest.id { open.state = .on }
            sub.addItem(open)
        }
        sub.addItem(.separator())
        let copy = NSMenuItem(title: "Copy link", action: #selector(copyLink(_:)), keyEquivalent: "")
        copy.target = self
        copy.representedObject = link.url
        sub.addItem(copy)
        item.submenu = sub
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func reopen(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? ReopenRequest else { return }
        state.open(request.url, in: request.target, remember: true, recentID: request.id)
    }

    @objc private func copyLink(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    @objc private func rebuild() { state.rebuildHistory() }
    @objc private func settings() { openSettings() }
    @objc private func setup() { openOnboarding() }
    @objc private func installUpdate() { Updater.shared.install() }
    @objc private func checkUpdates() {
        Updater.shared.check(userInitiated: true)
        openSettings()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

final class ReopenRequest: NSObject {
    let id: UUID
    let url: URL
    let target: DestinationID

    init(id: UUID, url: URL, target: DestinationID) {
        self.id = id
        self.url = url
        self.target = target
    }
}
