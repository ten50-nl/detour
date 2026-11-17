import AppIntents
import DetourCore
import Foundation

struct OpenLinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Open link with Detour"
    static let description = IntentDescription("Opens a link in the right browser and profile, just like clicking it in another app.")

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let state = AppDelegate.current?.state else { throw DetourIntentError.notRunning }
        state.handle(LinkContext(url: url, sourceApp: "Shortcuts"))
        return .result()
    }
}

struct WhereDoesLinkOpenIntent: AppIntent {
    static let title: LocalizedStringResource = "Where does a link open?"
    static let description = IntentDescription("Tells you which browser and profile Detour would use for a link, and why, without opening it.")

    @Parameter(title: "Link")
    var url: URL

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let state = AppDelegate.current?.state else { throw DetourIntentError.notRunning }
        let decision = state.engine.decide(LinkContext(url: state.rules.prepare(url)))
        let answer = decision.askUser
            ? "Detour would ask, suggesting \(state.label(decision.target)): \(decision.reason)."
            : "Opens in \(state.label(decision.target)): \(decision.reason)."
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

enum DetourIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        "Detour isn't running. Open Detour and try again."
    }
}

struct DetourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenLinkIntent(), phrases: ["Open a link with \(.applicationName)"],
                    shortTitle: "Open link", systemImageName: "arrow.triangle.branch")
        AppShortcut(intent: WhereDoesLinkOpenIntent(), phrases: ["Where does a link open in \(.applicationName)"],
                    shortTitle: "Where does it open?", systemImageName: "magnifyingglass")
    }
}
