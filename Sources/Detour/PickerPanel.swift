import AppKit
import DetourCore
import SwiftUI

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class PickerPanel: NSObject, NSWindowDelegate {
    private static var current: PickerPanel?

    private let panel: KeyablePanel
    private var completion: ((DestinationID?, Bool) -> Void)?
    private var monitor: Any?
    private let model: PickerModel

    static func show(url: URL, decision: Decision, destinations: [Destination], completion: @escaping (DestinationID?, Bool) -> Void) {
        current?.finish(nil)
        let picker = PickerPanel(url: url, decision: decision, destinations: destinations, completion: completion)
        current = picker
        picker.present()
    }

    private init(url: URL, decision: Decision, destinations: [Destination], completion: @escaping (DestinationID?, Bool) -> Void) {
        self.completion = completion
        let isFile = GoogleDecoder.fileID(in: url) != nil
        let host = normalizedHost(url) ?? url.absoluteString
        model = PickerModel(host: host, reason: decision.reason, selected: decision.target, destinations: Array(destinations.prefix(RulesConfig.maxDestinations)),
                            rememberLabel: isFile ? "Remember for this file" : "Remember for \(PathKey.key(for: url) ?? host)")
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                             styleMask: [.nonactivatingPanel, .borderless],
                             backing: .buffered, defer: false)
        super.init()
        model.choose = { [weak self] target in self?.finish(target) }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let hosting = NSHostingView(rootView: PickerView(model: model))
        let size = hosting.fittingSize
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        hosting.frame = glass.bounds
        hosting.autoresizingMask = [.width, .height]
        glass.addSubview(hosting)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = glass
        panel.setContentSize(size)
    }

    private func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height - 12)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: finish(nil); return true
        case 36, 76: finish(model.selected); return true
        case 123: model.move(-1); return true
        case 124: model.move(1); return true
        default: break
        }
        if let chars = event.charactersIgnoringModifiers, let n = Int(chars), n >= 1, n <= model.destinations.count {
            finish(model.destinations[n - 1].id)
            return true
        }
        return false
    }

    private func finish(_ target: DestinationID?) {
        guard let completion else { return }
        self.completion = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel.orderOut(nil)
        completion(target, model.remember)
        if Self.current === self { Self.current = nil }
    }

    func windowDidResignKey(_ notification: Notification) {
        finish(nil)
    }
}
