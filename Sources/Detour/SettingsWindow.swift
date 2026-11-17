import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    private struct Tab {
        let id: String
        let title: String
        let symbol: String
        let view: AnyView
    }

    init(state: AppState) {
        self.state = state
    }

    private var tabs: [Tab] {
        [
            Tab(id: "general", title: "General", symbol: "gearshape", view: AnyView(GeneralTab(state: state))),
            Tab(id: "destinations", title: "Destinations", symbol: "arrow.triangle.branch", view: AnyView(DestinationsTab(state: state).padding(20))),
            Tab(id: "apps", title: "Apps", symbol: "square.grid.2x2", view: AnyView(AppsTab(state: state).padding(20))),
            Tab(id: "learned", title: "Learned", symbol: "brain", view: AnyView(LearnedTab(state: state).padding(20))),
            Tab(id: "test", title: "Test a link", symbol: "magnifyingglass", view: AnyView(TestTab(state: state).padding(20))),
        ]
    }

    func show(tab: String? = nil) {
        if window == nil {
            let controller = NSTabViewController()
            controller.tabStyle = .toolbar
            controller.canPropagateSelectedChildViewControllerTitle = true
            for tab in tabs {
                let hosting = NSHostingController(rootView: tab.view.frame(width: 720, height: 540))
                hosting.sizingOptions = []
                hosting.preferredContentSize = NSSize(width: 720, height: 540)
                hosting.title = tab.title
                let item = NSTabViewItem(viewController: hosting)
                item.label = tab.title
                item.identifier = tab.id
                item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
                controller.addTabViewItem(item)
            }
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        let requested = tab ?? ProcessInfo.processInfo.environment["DETOUR_SETTINGS_TAB"]
        if let requested, let controller = window?.contentViewController as? NSTabViewController,
           let index = controller.tabViewItems.firstIndex(where: { ($0.identifier as? String) == requested }) {
            controller.selectedTabViewItemIndex = index
        }
        AppActivation.windowOpened()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.windowClosed(notification.object as? NSWindow)
    }
}
