import Foundation

public struct RoutingEngine: Sendable {
    public var rules: RulesConfig {
        didSet { compile() }
    }
    public var learned: LearnedStore
    public var history: HistoryIndex?
    public var tendencies: AppTendencies?
    public var appAvailable: (@Sendable (String) -> Bool)?

    private var explicit: [(DestinationID, HostPattern)] = []
    private var ambiguous: [HostPattern] = []

    public init(rules: RulesConfig, learned: LearnedStore = LearnedStore(), history: HistoryIndex? = nil) {
        self.rules = rules
        self.learned = learned
        self.history = history
        compile()
    }

    private mutating func compile() {
        explicit = rules.destinations.flatMap { dest in dest.patterns.map { (dest.id, HostPattern($0)) } }
        ambiguous = rules.askHosts.map(HostPattern.init)
    }

    public func decide(_ ctx: LinkContext) -> Decision {
        var decision = route(ctx)
        if ctx.forcePicker {
            decision.askUser = true
            decision.stage = .forced
            decision.reason = "you held option"
        }
        return decision
    }

    private func route(_ ctx: LinkContext) -> Decision {
        let url = ctx.url
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https", let host = normalizedHost(url) else {
            return Decision(target: fallback, stage: .fallback, reason: "not a web link")
        }

        if rules.openInApps, !ctx.forcePicker, let link = AppLinks.convert(url), appAvailable?(link.app) == true {
            return Decision(target: "", stage: .app, reason: "opens in the \(link.app) app", appURL: link.url)
        }

        if let (target, pattern) = explicit.first(where: { $0.1.matches(url) }) {
            return Decision(target: target, stage: .rule, reason: "matches your rule \(pattern.raw)")
        }

        if let always = sourceDecision(ctx, strengths: [.always]) { return always }

        if let email = GoogleDecoder.accountEmail(in: url), let target = accountTarget(email) {
            return Decision(target: target, stage: .decoder, reason: "google account \(email)")
        }
        if let id = GoogleDecoder.fileID(in: url), let target = history?.fileTarget(id) {
            return Decision(target: target, stage: .decoder, reason: "file opened before in \(name(target))")
        }

        if let (target, reason) = learned.lookup(url: url) {
            return Decision(target: target, stage: .learned, reason: reason)
        }

        let verdict = historyVerdict(url: url, host: host)
        if case let .confident(target, share, total) = verdict.verdict {
            return Decision(target: target, stage: .history, reason: "\(Int(share * 100))% of \(total) visits to \(verdict.label)")
        }

        let isAmbiguous = ambiguous.contains { $0.matches(url) }
        guard case let .mixed(counts) = verdict.verdict else {
            if isAmbiguous {
                if let tie = sourceDecision(ctx, strengths: [.whenUnsure, .tieBreaker]) ?? tendencyDecision(ctx) { return tie }
                return Decision(target: fallback, stage: .ambiguous, reason: "\(host) is used in more than one place", askUser: true)
            }
            if let fresh = sourceDecision(ctx, strengths: [.whenUnsure]) ?? tendencyDecision(ctx) { return fresh }
            return Decision(target: fallback, stage: .fallback, reason: "default")
        }

        if let tie = sourceDecision(ctx, strengths: [.whenUnsure, .tieBreaker]) ?? tendencyDecision(ctx) { return tie }
        let best = counts.max { $0.value < $1.value }?.key ?? fallback
        let summary = counts.sorted { $0.value > $1.value }.map { "\(name($0.key)) \($0.value)" }.joined(separator: ", ")
        return Decision(target: best, stage: .ambiguous, reason: "\(verdict.label) visits: \(summary)", askUser: true)
    }

    private func historyVerdict(url: URL, host: String) -> (verdict: HostVerdict, label: String) {
        guard let history else { return (.none, host) }
        if let key = PathKey.key(for: url) {
            let pathVerdict = history.pathVerdict(key)
            if case .confident = pathVerdict { return (pathVerdict, key) }
        }
        return (history.hostVerdict(host), host)
    }

    private func tendencyDecision(_ ctx: LinkContext) -> Decision? {
        guard let app = ctx.sourceApp, let tendency = tendencies?.target(for: app), rules.destination(tendency.target) != nil else { return nil }
        return Decision(target: tendency.target, stage: .source,
                        reason: "\(Int((tendency.share * 100).rounded()))% of your links from \(app) open in \(name(tendency.target))")
    }

    private var fallback: DestinationID {
        rules.destination(rules.defaultDestination) != nil ? rules.defaultDestination : (rules.destinations.first?.id ?? rules.defaultDestination)
    }

    private func name(_ id: DestinationID) -> String {
        rules.destination(id)?.name ?? id
    }

    private func accountTarget(_ email: String) -> DestinationID? {
        let email = email.lowercased()
        if let exact = rules.accountMap[email] { return exact }
        guard let domain = email.split(separator: "@").last.map(String.init) else { return nil }
        return rules.accountMap[domain]
    }

    private func sourceDecision(_ ctx: LinkContext, strengths: Set<SourceStrength>) -> Decision? {
        guard let app = ctx.sourceApp else { return nil }
        let candidates = rules.sourceRules.filter { strengths.contains($0.strength) && $0.app.caseInsensitiveCompare(app) == .orderedSame && rules.destination($0.target) != nil }
        guard !candidates.isEmpty else { return nil }
        let needsTitle = candidates.contains { !($0.titleContains ?? "").isEmpty }
        let title = needsTitle ? (ctx.sourceWindowTitle ?? ctx.titleProvider?()) : ctx.sourceWindowTitle
        guard let rule = candidates.first(where: { $0.matches(app: app, title: title) }) else { return nil }
        let strength = switch rule.strength {
        case .always: "always"
        case .whenUnsure: "for new and unclear sites"
        case .tieBreaker: "as a tie-breaker"
        }
        return Decision(target: rule.target, stage: .source, reason: "links from \(app) go to \(name(rule.target)) (\(strength))")
    }
}
