import Foundation

public struct RoutingEngine: Sendable {
    public var rules: RulesConfig {
        didSet { compile() }
    }
    public var learned: LearnedStore
    public var history: HistoryIndex?

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

        if let (target, pattern) = explicit.first(where: { $0.1.matches(url) }) {
            return Decision(target: target, stage: .rule, reason: "matches your rule \(pattern.raw)")
        }

        if let email = GoogleDecoder.accountEmail(in: url), let target = accountTarget(email) {
            return Decision(target: target, stage: .decoder, reason: "google account \(email)")
        }
        if let id = GoogleDecoder.fileID(in: url), let target = history?.fileTarget(id) {
            return Decision(target: target, stage: .decoder, reason: "file opened before in \(name(target))")
        }

        if let (target, reason) = learned.lookup(url: url) {
            return Decision(target: target, stage: .learned, reason: reason)
        }

        let verdict = history?.hostVerdict(host) ?? .none
        if case let .confident(target, share, total) = verdict {
            return Decision(target: target, stage: .history, reason: "\(Int(share * 100))% of \(total) visits to \(host)")
        }

        let isAmbiguous = ambiguous.contains { $0.matches(url) }
        guard case let .mixed(counts) = verdict else {
            if isAmbiguous {
                return sourceDecision(ctx) ?? Decision(target: fallback, stage: .ambiguous, reason: "\(host) is used in more than one place", askUser: true)
            }
            return Decision(target: fallback, stage: .fallback, reason: "default")
        }

        if let source = sourceDecision(ctx) { return source }
        let best = counts.max { $0.value < $1.value }?.key ?? fallback
        let summary = counts.sorted { $0.value > $1.value }.map { "\(name($0.key)) \($0.value)" }.joined(separator: ", ")
        return Decision(target: best, stage: .ambiguous, reason: "\(host) visits: \(summary)", askUser: true)
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

    private func sourceDecision(_ ctx: LinkContext) -> Decision? {
        guard let app = ctx.sourceApp else { return nil }
        let candidates = rules.sourceRules.filter { $0.app.caseInsensitiveCompare(app) == .orderedSame }
        guard !candidates.isEmpty else { return nil }
        let title = (ctx.sourceWindowTitle ?? ctx.titleProvider?())?.lowercased() ?? ""
        let rule = candidates.first { rule in
            guard let needle = rule.titleContains?.lowercased() else { return true }
            return title.contains(needle)
        }
        guard let rule else { return nil }
        return Decision(target: rule.target, stage: .source, reason: "link from \(app)")
    }
}
