import AppKit
import DetourCore
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, fullDiskAccess, destinations, smartStart, defaultBrowser, finishing, done
    }

    let state: AppState
    var onFinish: () -> Void = {}

    @Published var step: Step = .welcome
    @Published var fda = Permissions.hasFullDiskAccess
    @Published var isDefault = Permissions.isDefaultBrowser
    @Published var accessibility = Permissions.hasAccessibility
    @Published var candidates: [Destination] = []
    @Published var selected: Set<DestinationID> = []
    @Published var defaultID: DestinationID = ""
    @Published var suggestions: [DestinationID: [RuleSuggestion]] = [:]
    @Published var accepted: Set<String> = []
    @Published var videoTarget: DestinationID?
    @Published var appSuggestions: [SourceRule] = []
    @Published var acceptedApps: Set<String> = []
    @Published var loadingSuggestions = false
    @Published var imported = false
    @Published var launchAtLogin = true
    @Published var tryResult: String?
    @Published var error: String?

    private var poll: Timer?

    init(state: AppState) {
        self.state = state
        if state.hasConfig {
            candidates = state.destinations
            selected = Set(state.destinations.map(\.id))
            defaultID = state.rules.defaultDestination
        }
        if let raw = ProcessInfo.processInfo.environment["DETOUR_ONBOARDING_STEP"], let jump = Step.allCases.first(where: { "\($0)" == raw }) {
            DispatchQueue.main.async { self.enter(jump) }
        }
    }

    var canImport: Bool { state.legacyAvailable && !imported && !state.hasConfig && !BrowserScanner.isDemo }
    var visibleSteps: [Step] { Step.allCases.filter { !skipped($0) } }

    func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
    }

    func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    func refreshPermissions() {
        let hadFDA = fda
        fda = Permissions.hasFullDiskAccess
        isDefault = Permissions.isDefaultBrowser
        accessibility = Permissions.hasAccessibility
        if fda && !hadFDA && step == .fullDiskAccess { scanBrowsers() }
    }

    func skipped(_ step: Step) -> Bool {
        switch step {
        case .destinations: imported
        case .smartStart: imported || !fda || state.historySources(for: candidates.filter { selected.contains($0.id) }).count < 2
        case .defaultBrowser: Paths.isIsolated
        default: false
        }
    }

    func next() {
        leave(step)
        var candidate = step.rawValue + 1
        while let s = Step(rawValue: candidate), skipped(s) { candidate += 1 }
        guard let s = Step(rawValue: candidate) else { return finish() }
        enter(s)
    }

    func back() {
        var candidate = step.rawValue - 1
        while let s = Step(rawValue: candidate), skipped(s) { candidate -= 1 }
        if let s = Step(rawValue: candidate) { step = s }
    }

    func importLegacy() {
        imported = state.importLegacy()
        if imported {
            candidates = state.destinations
            selected = Set(candidates.map(\.id))
            defaultID = state.rules.defaultDestination
            next()
        } else {
            error = "Could not read your LinkRouter settings."
        }
    }

    var canContinue: Bool {
        switch step {
        case .destinations:
            !selected.isEmpty && selected.count <= RulesConfig.maxDestinations && selected.contains(defaultID)
                && candidates.contains { $0.id == defaultID }
        default: true
        }
    }

    private func enter(_ s: Step) {
        step = s
        switch s {
        case .destinations: scanBrowsers()
        case .smartStart: loadSuggestions()
        default: break
        }
    }

    private func leave(_ s: Step) {
        switch s {
        case .destinations: saveDestinations()
        case .smartStart: saveSuggestions()
        case .finishing: try? Permissions.setLaunchAtLogin(launchAtLogin)
        default: break
        }
    }

    func scanBrowsers() {
        let saved = candidates.isEmpty ? state.destinations : candidates
        candidates = DestinationMerge.merge(saved: saved, scanned: BrowserScanner.candidates())
        let ids = Set(candidates.map(\.id))
        selected = selected.intersection(ids)
        if selected.isEmpty {
            selected = Set(preselect(candidates).prefix(RulesConfig.maxDestinations).map(\.id))
        }
        if !selected.contains(defaultID) { defaultID = preferredDefault(candidates.filter { selected.contains($0.id) }) }
    }

    private func preselect(_ all: [Destination]) -> [Destination] {
        let current = state.destinations.isEmpty ? Permissions.currentDefaultBrowserBundleID : nil
        let chromium = all.filter { $0.isProfile }
        let chromiumApps = all.filter { ChromiumFamily.supportDirs[$0.bundleID] != nil }
        let family = chromiumApps.first { $0.bundleID == current }?.bundleID ?? chromium.first?.bundleID ?? chromiumApps.first?.bundleID
        return all.filter { $0.bundleID == family || ChromiumFamily.supportDirs[$0.bundleID] == nil }
    }

    private func preferredDefault(_ chosen: [Destination]) -> DestinationID {
        let current = Permissions.currentDefaultBrowserBundleID
        return chosen.first { $0.bundleID == current && ($0.profileDir == nil || $0.profileDir == "Default") }?.id
            ?? chosen.first { $0.bundleID == current }?.id
            ?? chosen.first?.id ?? ""
    }

    func move(from: IndexSet, to: Int) {
        candidates.move(fromOffsets: from, toOffset: to)
    }

    private func saveDestinations() {
        let chosen = candidates.filter { selected.contains($0.id) }
        guard !chosen.isEmpty, chosen.count <= RulesConfig.maxDestinations, chosen.contains(where: { $0.id == defaultID }) else { return }
        var rules = state.rules
        rules.destinations = chosen
        rules.defaultDestination = defaultID
        rules.accountMap = Suggestions.accountMap(destinations: rules.destinations).merging(rules.accountMap) { derived, _ in derived }
        state.updateRules(rules)
    }

    private func loadSuggestions() {
        let installed = BrowserScanner.isDemo ? ["Slack", "Microsoft Teams", "Messages", "WhatsApp"] : InstalledApps.names()
        appSuggestions = Suggestions.appRules(installedApps: installed, destinations: state.destinations,
                                              defaultID: state.rules.defaultDestination, existing: state.rules.sourceRules)
        if BrowserScanner.isDemo {
            suggestions = BrowserScanner.demoSuggestions(destinations: state.destinations, defaultID: state.rules.defaultDestination)
            accepted = Set(suggestions.values.flatMap { $0 }.map { "\($0.destination)|\($0.host)" })
            return
        }
        loadingSuggestions = true
        state.rebuildHistory { [weak self] in
            guard let self else { return }
            let index = self.state.engine.history ?? HistoryIndex()
            self.suggestions = Suggestions.rules(index: index, destinations: self.state.destinations, defaultID: self.state.rules.defaultDestination)
            self.accepted = Set(self.suggestions.values.flatMap { $0 }.map { "\($0.destination)|\($0.host)" })
            self.loadingSuggestions = false
        }
    }

    var videoCandidates: [Destination] {
        state.destinations.filter { !$0.isProfile && $0.id != state.rules.defaultDestination }
    }

    private func saveSuggestions() {
        var rules = state.rules
        for i in rules.destinations.indices {
            let id = rules.destinations[i].id
            let offered = suggestions[id] ?? []
            let hosts = offered.filter { accepted.contains("\(id)|\($0.host)") }.map(\.host)
            let declined = Set(offered.map(\.host)).subtracting(hosts)
            var patterns = rules.destinations[i].patterns.filter { !declined.contains($0) }
            for host in hosts where !patterns.contains(host) { patterns.append(host) }
            if id == videoTarget {
                for host in Suggestions.videoPreset where !patterns.contains(host) { patterns.append(host) }
            }
            rules.destinations[i].patterns = patterns
        }
        rules.sourceRules += appSuggestions.filter { acceptedApps.contains($0.app) }
        state.updateRules(rules)
    }

    func makeDefault() {
        Task {
            do { try await Permissions.makeDefaultBrowser() } catch { self.error = error.localizedDescription }
            refreshPermissions()
        }
    }

    func tryLink() {
        let url = URL(string: "https://ten50.nl/")!
        let decision = state.engine.decide(LinkContext(url: url))
        tryResult = "ten50.nl opens in \(state.label(decision.target)): \(decision.reason)."
        state.handle(LinkContext(url: url, sourceApp: "Detour"))
    }

    func finish() {
        stopPolling()
        state.markOnboardingDone()
        onFinish()
    }
}
