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
    public var privateWindow: Bool

    public init(id: DestinationID, name: String, appPath: String, bundleID: String, profileDir: String? = nil,
                profileName: String? = nil, account: String? = nil, color: String = "#8E8E93", patterns: [String] = [], privateWindow: Bool = false) {
        self.id = id
        self.name = name
        self.appPath = appPath
        self.bundleID = bundleID
        self.profileDir = profileDir
        self.profileName = profileName
        self.account = account
        self.color = color
        self.patterns = patterns
        self.privateWindow = privateWindow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(DestinationID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        appPath = try c.decode(String.self, forKey: .appPath)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        profileDir = try c.decodeIfPresent(String.self, forKey: .profileDir)
        profileName = try c.decodeIfPresent(String.self, forKey: .profileName)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#8E8E93"
        patterns = try c.decodeIfPresent([String].self, forKey: .patterns) ?? []
        privateWindow = try c.decodeIfPresent(Bool.self, forKey: .privateWindow) ?? false
    }

    public var isProfile: Bool { profileDir != nil }
}
