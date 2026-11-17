import Foundation
import Testing
@testable import DetourCore

@Suite struct BrowserDiscoveryTests {
    let chrome = BrowserApp(bundleID: "com.google.Chrome", name: "Google Chrome", appPath: "/Applications/Google Chrome.app")
    let brave = BrowserApp(bundleID: "com.brave.Browser", name: "Brave Browser", appPath: "/Applications/Brave Browser.app")
    let firefox = BrowserApp(bundleID: "org.mozilla.firefox", name: "Firefox", appPath: "/Applications/Firefox.app")
    let detour = BrowserApp(bundleID: "nl.ten50.detour", name: "Detour", appPath: "/Applications/Detour.app")

    @Test func parsesProfilesWithEmailsInOrder() {
        let json = #"{"profile":{"info_cache":{"Profile 10":{"name":"Ten","user_name":""},"Default":{"name":"Me","user_name":"me@gmail.com"},"Profile 2":{"name":"Work","user_name":"me@acme.com"}}}}"#
        let profiles = ChromeProfiles.profiles(localStateData: Data(json.utf8))
        #expect(profiles.map(\.dir) == ["Default", "Profile 2", "Profile 10"])
        #expect(profiles[0].email == "me@gmail.com")
        #expect(profiles[2].email == nil)
    }

    @Test func duplicateProfileNamesStayDistinct() {
        let profiles = [ProfileInfo(dir: "Default", name: "Person 1", email: nil), ProfileInfo(dir: "Profile 1", name: "Person 1", email: nil)]
        let found = BrowserDiscovery.candidates(apps: [chrome], profiles: { _ in profiles })
        #expect(found.count == 2)
        #expect(Set(found.map(\.id)).count == 2)
        #expect(found.map(\.profileDir) == ["Default", "Profile 1"])
        #expect(found.allSatisfy { $0.name == "Person 1" && $0.profileName == "Person 1" })
    }

    @Test func chromiumWithoutReadableProfilesIsOneDestination() {
        let found = BrowserDiscovery.candidates(apps: [brave], profiles: { _ in nil })
        #expect(found.count == 1)
        #expect(found[0].profileDir == nil)
        #expect(found[0].name == "Brave Browser")
    }

    @Test func otherBrowsersAreWholeAppsAndDetourIsExcluded() {
        let found = BrowserDiscovery.candidates(apps: [firefox, detour], profiles: { _ in nil })
        #expect(found.map(\.bundleID) == ["org.mozilla.firefox"])
        #expect(found[0].id == "firefox")
    }

    @Test func accountAndColorsAreSet() {
        let found = BrowserDiscovery.candidates(apps: [chrome, firefox], profiles: { app in
            app.bundleID == "com.google.Chrome" ? [ProfileInfo(dir: "Default", name: "Me", email: "me@acme.com")] : nil
        })
        #expect(found[0].account == "me@acme.com")
        #expect(found[0].id == "google-chrome-default")
        #expect(found[0].color != found[1].color)
    }

    @Test func supportDirTable() {
        #expect(ChromiumFamily.supportDirs["com.brave.Browser"] == "BraveSoftware/Brave-Browser")
        #expect(ChromiumFamily.supportDirs["com.google.Chrome"] == "Google/Chrome")
        #expect(ChromiumFamily.supportDirs["com.microsoft.edgemac"] == "Microsoft Edge")
        #expect(ChromiumFamily.supportDirs["org.mozilla.firefox"] == nil)
    }
}
