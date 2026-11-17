import Foundation

public struct LinkContext: Sendable {
    public var url: URL
    public var sourceApp: String?
    public var sourceWindowTitle: String?
    public var forcePicker: Bool
    public var titleProvider: (@Sendable () -> String?)?

    public init(url: URL, sourceApp: String? = nil, sourceWindowTitle: String? = nil, forcePicker: Bool = false, titleProvider: (@Sendable () -> String?)? = nil) {
        self.url = url
        self.sourceApp = sourceApp
        self.sourceWindowTitle = sourceWindowTitle
        self.forcePicker = forcePicker
        self.titleProvider = titleProvider
    }
}

public enum Stage: String, Codable, Sendable {
    case forced, rule, decoder, learned, history, source, ambiguous, fallback
}

public struct Decision: Equatable, Sendable {
    public var target: DestinationID
    public var stage: Stage
    public var reason: String
    public var askUser: Bool

    public init(target: DestinationID, stage: Stage, reason: String, askUser: Bool = false) {
        self.target = target
        self.stage = stage
        self.reason = reason
        self.askUser = askUser
    }
}
