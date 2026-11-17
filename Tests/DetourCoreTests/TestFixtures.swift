import Foundation
@testable import DetourCore

extension RulesConfig {
    static let fixture = RulesConfig(
        destinations: [
            Destination(id: "work", name: "Work", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome",
                        profileDir: "Profile 1", profileName: "Work", account: "me@acme.com", color: "#4F8BFF",
                        patterns: ["~acme", "acme-corp.atlassian.net", "planningpokeronline.com", "meet.google.com"]),
            Destination(id: "ads", name: "Ad-free", appPath: "/Applications/Firefox.app", bundleID: "org.mozilla.firefox",
                        color: "#FF7A1A", patterns: ["youtube.com", "youtu.be", "dumpert.nl"]),
            Destination(id: "personal", name: "Personal", appPath: "/Applications/Google Chrome.app", bundleID: "com.google.Chrome",
                        profileDir: "Default", profileName: "Me", color: "#34C759", patterns: ["linkedin.com", "reddit.com"]),
        ],
        defaultDestination: "personal",
        accountMap: ["acme.com": "work", "me@gmail.com": "personal"],
        sourceRules: [
            SourceRule(app: "Ferdium", titleContains: "Mattermost", target: "work"),
            SourceRule(app: "Ferdium", titleContains: "WhatsApp", target: "personal"),
        ],
        askHosts: RulesConfig.empty.askHosts
    )
}
