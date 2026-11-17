import AppKit
import ApplicationServices

@MainActor
enum SourceContext {
    private static var lastOtherApp: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    static func startTracking() {
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own { lastOtherApp = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != own else { return }
            MainActor.assumeIsolated { lastOtherApp = app }
        }
    }

    static func capture(senderPID: pid_t?) -> (app: String?, title: (@Sendable () -> String?)?) {
        let own = ProcessInfo.processInfo.processIdentifier
        var candidate: NSRunningApplication?
        if let pid = senderPID, pid != own, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            candidate = app
        }
        if candidate == nil, let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            candidate = front
        }
        if candidate == nil, let last = lastOtherApp, !last.isTerminated {
            candidate = last
        }
        guard let app = candidate else { return (nil, nil) }
        let pid = app.processIdentifier
        return (app.localizedName, { focusedWindowTitle(pid: pid) })
    }

    nonisolated static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.05)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}
