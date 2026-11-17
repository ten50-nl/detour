import Foundation
import Testing
@testable import DetourCore

func base64url(_ s: String) -> String {
    Data(s.utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@Suite struct GoogleDecoderTests {
    let docID = "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms"

    @Test func calendarEid() {
        let eid = base64url("abc123def colleague@acme.com")
        let url = URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")!
        #expect(GoogleDecoder.accountEmail(in: url) == "colleague@acme.com")
        let legacy = URL(string: "https://www.google.com/calendar/event?eid=\(eid)")!
        #expect(GoogleDecoder.accountEmail(in: legacy) == "colleague@acme.com")
    }

    @Test func calendarEidGmailShorthand() {
        let eid = base64url("abc123def me@m")
        let url = URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")!
        #expect(GoogleDecoder.accountEmail(in: url) == "me@gmail.com")
    }

    @Test func authuserEmail() {
        let url = URL(string: "https://docs.google.com/document/d/\(docID)/edit?authuser=me@gmail.com")!
        #expect(GoogleDecoder.accountEmail(in: url) == "me@gmail.com")
    }

    @Test func numericAuthuserIgnored() {
        #expect(GoogleDecoder.accountEmail(in: URL(string: "https://docs.google.com/document/d/\(docID)/edit?authuser=1")!) == nil)
        #expect(GoogleDecoder.accountEmail(in: URL(string: "https://mail.google.com/mail/u/1/")!) == nil)
    }

    @Test(arguments: ["!!!", base64url("noemail"), base64url(""), base64url("id notanemail")])
    func badEid(eid: String) {
        let url = URL(string: "https://calendar.google.com/calendar/event?eid=\(eid)")!
        #expect(GoogleDecoder.accountEmail(in: url) == nil)
    }

    @Test func fileIDFromPath() {
        #expect(GoogleDecoder.fileID(in: URL(string: "https://docs.google.com/spreadsheets/d/\(docID)/edit#gid=0")!) == docID)
        #expect(GoogleDecoder.fileID(in: URL(string: "https://drive.google.com/open?id=\(docID)")!) == docID)
        #expect(GoogleDecoder.fileID(in: URL(string: "https://drive.google.com/file/d/\(docID)/view")!) == docID)
        #expect(GoogleDecoder.fileID(in: URL(string: "https://example.com/d/\(docID)")!) == nil)
        #expect(GoogleDecoder.fileID(in: URL(string: "https://docs.google.com/document/d/short/edit")!) == nil)
    }
}
