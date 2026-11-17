import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?
    private var model: OnboardingModel?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if window == nil {
            let model = OnboardingModel(state: state)
            model.onFinish = { [weak self] in self?.window?.close() }
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: OnboardingView(model: model))
            window.center()
            self.window = window
            self.model = model
        }
        AppActivation.windowOpened()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopPolling()
        AppActivation.windowClosed(notification.object as? NSWindow)
        window = nil
        model = nil
    }
}
