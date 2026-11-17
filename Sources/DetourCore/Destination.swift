import Foundation

public typealias DestinationID = String

public struct Destination: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: DestinationID
    public var name: String
    public var appPath: String
    public var bundleID: String
    public var profileDir: String?
    public var profileName: String?
    public var account: String?
    public var color: String
    public var patterns: [String]

    public init(id: DestinationID, name: String, appPath: String, bundleID: String, profileDir: String? = nil,
                profileName: String? = nil, account: String? = nil, color: String = "#8E8E93", patterns: [String] = []) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.bundleID = bundleID
        self.profileDir = profileDir
        self.profileName = profileName
        self.account = account
        self.color = color
        self.patterns = patterns
    }

    public var isProfile: Bool { profileDir != nil }
}
