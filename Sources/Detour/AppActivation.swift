import AppKit

@MainActor
enum AppActivation {
    static func windowOpened() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func windowClosed(_ closing: NSWindow?) {
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}
