import Contracts
import Foundation
import Testing

struct InviteLinkTests {
    @Test func linkCarriesTheCode() throws {
        let code = try InviteCode("k7m2qx9p")
        #expect(InviteLink.url(for: code).absoluteString == "https://wildcardsquad.com/join/K7M2QX9P")
        #expect(InviteLink.code(in: InviteLink.url(for: code)) == code)
    }

    @Test(arguments: [
        "https://wildcardsquad.com/join/k7m2qx9p",
        "https://www.wildcardsquad.com/join/K7M2QX9P/",
        "https://WildcardSquad.com/join/K7M2QX9P?lang=en",
    ])
    func readsTheCodeFromALink(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InviteLink.code(in: url)?.text == "K7M2QX9P")
    }

    @Test(arguments: [
        "http://wildcardsquad.com/join/K7M2QX9P",
        "https://example.com/join/K7M2QX9P",
        "https://wildcardsquad.com/zh/join/K7M2QX9P",
        "https://wildcardsquad.com/join/",
        "https://wildcardsquad.com/join/K7M2QX0P",
        "https://wildcardsquad.com/privacy",
    ])
    func ignoresOtherLinks(link: String) throws {
        let url = try #require(URL(string: link))
        #expect(InviteLink.code(in: url) == nil)
    }
}
