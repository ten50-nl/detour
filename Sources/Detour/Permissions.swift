import AppKit
import ApplicationServices
import DetourCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
enum Permissions {
    static var hasFullDiskAccess: Bool {
        Paths.fullDiskAccessProbes.contains { FileManager.default.fileExists(atPath: $0.path) && AccessCheck.canRead($0) }
    }
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    static var isDefaultBrowser: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static var currentDefaultBrowserBundleID: String? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    static func makeDefaultBrowser() async throws {
        let app = Bundle.main.bundleURL
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http")
        try await NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "https")
        try? await NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .html)
    }

    static var canUseLoginItem: Bool {
        !Paths.isIsolated && Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var launchesAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ on: Bool) throws {
        guard canUseLoginItem else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
