import Foundation
import Testing
@testable import DetourCore

@Suite struct HostPatternTests {
    @Test(arguments: [
        ("https://git.acme.io/x", "~acme"),
        ("HTTPS://Git.Acme.IO./x", "~acme"),
        ("https://www.youtube.com/watch?v=1", "youtube.com"),
        ("https://m.youtube.com/", "youtube.com"),
        ("http://cms.shop.test/", "*.shop.test"),
        ("http://shop249.test/", "shop*.test"),
        ("https://staging.app.hosting.io/", "~.app."),
        ("https://ppv.rw/live", "ppv.*"),
        ("https://app-dev.test/", "app-*.test"),
        ("https://my.hosting.com/", "hosting.com"),
        ("https://planningpokeronline.com/room/1", "url:*planningpoker*"),
    ])
    func matches(url: String, pattern: String) {
        #expect(HostPattern(pattern).matches(URL(string: url)!))
    }

    @Test(arguments: [
        ("https://shop.nl/", "shop*.test"),
        ("https://dapp.nl/", "app.test"),
        ("https://notyoutube.com/", "youtube.com"),
        ("https://ppv.rw.evil.com/", "ppv.*"),
        ("https://acme.com/", "url:*planningpoker*"),
    ])
    func nonMatches(url: String, pattern: String) {
        #expect(!HostPattern(pattern).matches(URL(string: url)!))
    }

    @Test func normalizesHost() {
        #expect(normalizedHost(URL(string: "HTTPS://WWW.Git.Acme.IO./x")!) == "git.acme.io")
        #expect(normalizedHost(URL(string: "mailto:x@y.z")!) == nil)
    }
}
