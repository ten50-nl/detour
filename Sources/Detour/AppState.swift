import AppKit
import Combine
import DetourCore

struct RecentLink: Identifiable {
    let id = UUID()
    let url: URL
    let date: Date
    let sourceApp: String?
    let decision: Decision
    var opened: DestinationID?
}

@MainActor
final class AppState: ObservableObject {
    static let maxRecent = 20
    static let historyInterval: TimeInterval = 30 * 60

    @Published private(set) var engine: RoutingEngine
    @Published private(set) var recent: [RecentLink] = []
    @Published private(set) var rulesError: String?
    @Published private(set) var historyStatus: HistoryStatus = .unknown
    @Published private(set) var profileWarnings: [DestinationID: String] = [:]

    enum HistoryStatus: Equatable {
        case unknown
        case noAccess
        case building
        case ready(hosts: Int, builtAt: Date)
        case failed(String)
    }

    var presentPicker: ((URL, Decision, @escaping (DestinationID?, Bool) -> Void) -> Void)?
    var onRecentChange: (() -> Void)?

    private var blocked: Set<DestinationID> = []
    private var historyTimer: Timer?
    private var rulesWatcher: DispatchSourceFileSystemObject?
    private var rulesDetector = FileChangeDetector(url: Paths.rules)
    private var rebuilding = false

    var rules: RulesConfig { engine.rules }
    var destinations: [Destination] { engine.rules.destinations }

    static let onboardingMarker = Paths.support.appendingPathComponent(".onboarding-done")

    var hasConfig: Bool { FileManager.default.fileExists(atPath: Paths.rules.path) && !destinations.isEmpty }
    var onboardingDone: Bool { FileManager.default.fileExists(atPath: Self.onboardingMarker.path) }
    var legacyAvailable: Bool { FileManager.default.fileExists(atPath: Paths.legacyRules.path) }

    init() {
        let (rules, error) = ConfigLoader.loadRules(from: Paths.rules, fallback: .empty)
        let learned = (try? JSONDecoder().decode(LearnedStore.self, from: Data(contentsOf: Paths.learned))) ?? LearnedStore()
        let history = try? JSONDecoder().decode(HistoryIndex.self, from: Data(contentsOf: Paths.historyIndex))
        engine = RoutingEngine(rules: rules, learned: learned, history: history)
        rulesError = error.map { "rules.json could not be read: \($0.localizedDescription)" }
        if error != nil { Self.backUpBrokenRules() }
        if let history { historyStatus = .ready(hosts: history.hosts.count, builtAt: history.builtAt) }
    }

    private static func backUpBrokenRules() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = Paths.support.appendingPathComponent("rules.broken-\(stamp).json")
        try? FileManager.default.copyItem(at: Paths.rules, to: backup)
    }

    var rulesFileBroken: Bool { rulesError != nil && FileManager.default.fileExists(atPath: Paths.rules.path) }

    func start() {
        DecisionLog.prune()
        watchRules()
        rebuildHistory()
        historyTimer = Timer.scheduledTimer(withTimeInterval: Self.historyInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rebuildHistory() }
        }
    }

    func label(_ id: DestinationID) -> String {
        engine.rules.displayNames()[id] ?? (id.isEmpty ? "your browser" : id)
    }

    func handle(_ ctx: LinkContext) {
        if rulesDetector.hasChanged() { reloadRules() }
        let decision = engine.decide(ctx)
        var link = RecentLink(url: ctx.url, date: Date(), sourceApp: ctx.sourceApp, decision: decision)
        if decision.askUser, destinations.count > 1, let presentPicker {
            addRecent(link)
            presentPicker(ctx.url, decision) { target, remember in
                if let target { self.open(ctx.url, in: target, remember: remember, recentID: link.id) }
                self.log(ctx, target: target, stage: decision.stage, asked: true)
            }
            return
        }
        link.opened = decision.target
        addRecent(link)
        log(ctx, target: decision.target, stage: decision.stage, asked: false)
        launch(ctx.url, in: decision.target)
    }

    func open(_ url: URL, in target: DestinationID, remember: Bool, recentID: UUID? = nil) {
        if remember {
            var learned = engine.learned
            learned.remember(url: url, target: target)
            engine.learned = learned
            try? ConfigLoader.save(learned, to: Paths.learned)
        }
        if let recentID, let i = recent.firstIndex(where: { $0.id == recentID }) {
            recent[i].opened = target
            onRecentChange?()
        }
        launch(url, in: target)
    }

    func forget(host: String? = nil, fileID: String? = nil) {
        var learned = engine.learned
        if let host { learned.hosts[host] = nil }
        if let fileID { learned.fileIDs[fileID] = nil }
        engine.learned = learned
        try? ConfigLoader.save(learned, to: Paths.learned)
    }

    func updateRules(_ newRules: RulesConfig) {
        let rules = newRules.pruned()
        try? ConfigLoader.save(rules, to: Paths.rules)
        _ = rulesDetector.hasChanged()
        engine.rules = rules
        let learned = engine.learned.pruned(validIDs: Set(rules.destinations.map(\.id)))
        if learned != engine.learned {
            engine.learned = learned
            try? ConfigLoader.save(learned, to: Paths.learned)
        }
        rulesError = nil
        checkProfiles()
    }

    func markOnboardingDone() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.onboardingMarker.path, contents: Data())
    }

    func importLegacy() -> Bool {
        guard let data = try? Data(contentsOf: Paths.legacyRules), let rules = try? LegacyImport.rules(fromV1: data) else { return false }
        updateRules(rules)
        if let learnedData = try? Data(contentsOf: Paths.legacyLearned), let learned = try? LegacyImport.learned(fromV1: learnedData) {
            engine.learned = learned
            try? ConfigLoader.save(learned, to: Paths.learned)
        }
        return true
    }

    func reloadRules() {
        let (rules, error) = ConfigLoader.loadRules(from: Paths.rules, fallback: engine.rules)
        engine.rules = rules
        rulesError = error.map { "rules.json could not be read, using the last good rules: \($0.localizedDescription)" }
        checkProfiles()
    }

    private var historyWaiters: [() -> Void] = []

    func rebuildHistory(completion: (() -> Void)? = nil) {
        if let completion { historyWaiters.append(completion) }
        guard Permissions.hasFullDiskAccess else {
            historyStatus = .noAccess
            Notifier.fullDiskAccessLost()
            flushWaiters()
            return
        }
        Notifier.fullDiskAccessWorks()
        checkProfiles()
        guard !rebuilding else { return }
        let sources = historySources(for: destinations)
        guard !sources.isEmpty else { flushWaiters(); return }
        rebuilding = true
        historyStatus = .building
        let cache = Paths.cache
        Task.detached(priority: .utility) {
            let result = Result { try HistoryIndexer(cacheDir: cache).build(sources: sources, now: Date()) }
            await self.finishRebuild(result)
        }
    }

    private func finishRebuild(_ result: Result<HistoryIndex, Error>) {
        rebuilding = false
        switch result {
        case .success(let index):
            try? ConfigLoader.save(index, to: Paths.historyIndex)
            engine.history = index
            historyStatus = .ready(hosts: index.hosts.count, builtAt: index.builtAt)
        case .failure(let error):
            historyStatus = .failed(String(describing: error))
        }
        flushWaiters()
    }

    private func flushWaiters() {
        let waiters = historyWaiters
        historyWaiters = []
        waiters.forEach { $0() }
    }

    nonisolated func historySources(for destinations: [Destination]) -> [HistorySource] {
        var sources: [HistorySource] = []
        for dest in destinations {
            if let dir = dest.profileDir, let root = ChromiumFamily.supportDir(for: dest.bundleID, appSupport: Paths.appSupport) {
                sources.append(HistorySource(target: dest.id, kind: .chrome, dbPath: root.appendingPathComponent(dir).appendingPathComponent("History")))
            } else if dest.bundleID == "org.mozilla.firefox",
                      let ini = try? String(contentsOf: Paths.firefoxRoot.appendingPathComponent("profiles.ini"), encoding: .utf8),
                      let profile = FirefoxProfiles.defaultProfilePath(iniText: ini, baseDir: Paths.firefoxRoot) {
                sources.append(HistorySource(target: dest.id, kind: .firefox, dbPath: profile.appendingPathComponent("places.sqlite")))
            }
        }
        return sources
    }

    private func checkProfiles() {
        var problems: [DestinationID: ProfileProblem] = [:]
        for bundleID in Set(destinations.compactMap { $0.profileDir == nil ? nil : $0.bundleID }) {
            guard let url = Paths.localState(for: bundleID), let data = try? Data(contentsOf: url) else { continue }
            let names = ChromeProfiles.displayNames(localStateData: data)
            let found = ProfileCheck.problems(destinations: destinations.filter { $0.bundleID == bundleID }, names: names)
            problems.merge(found) { a, _ in a }
        }
        let warnings = problems.mapValues(\.message)
        blocked = Set(problems.filter { $0.value.blocksRouting }.keys)
        for (id, text) in warnings where profileWarnings[id] != text {
            Notifier.profileMismatch(name: label(id), detail: text)
        }
        profileWarnings = warnings
    }

    private func launch(_ url: URL, in target: DestinationID) {
        let chain = openChain(target, default: engine.rules.defaultDestination)
            .filter { !blocked.contains($0) }
            .compactMap { engine.rules.destination($0) }
        Task { @MainActor in
            for dest in chain {
                if (try? await DestinationOpener.open(url, destination: dest)) != nil { return }
            }
            if await DestinationOpener.openAnywhere(url) { return }
            Notifier.openFailed(url: url)
        }
    }

    private func addRecent(_ link: RecentLink) {
        recent.insert(link, at: 0)
        if recent.count > Self.maxRecent { recent.removeLast(recent.count - Self.maxRecent) }
        onRecentChange?()
    }

    private func log(_ ctx: LinkContext, target: DestinationID?, stage: Stage, asked: Bool) {
        DecisionLog.append(.init(time: Date(), host: normalizedHost(ctx.url) ?? ctx.url.absoluteString, sourceApp: ctx.sourceApp, target: target, stage: stage.rawValue, asked: asked))
    }

    private func watchRules() {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let fd = Darwin.open(Paths.support.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.rulesDetector.hasChanged() else { return }
                self.reloadRules()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        rulesWatcher = source
    }
}
