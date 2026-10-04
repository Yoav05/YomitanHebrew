import Foundation
import Testing
@testable import YomitanCore

@Suite("Pealim client")
struct PealimClientTests {
    @Test("Builds a Russian search URL and trims the query")
    func buildsRussianSearchURLAndTrimsQuery() throws {
        let client = PealimClient()

        let url = try client.searchURL(for: "  לְחַפֵּשׂ  ")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "www.pealim.com")
        #expect(components.path == "/ru/search/")
        #expect(components.queryItems == [URLQueryItem(name: "q", value: "לְחַפֵּשׂ")])
    }

    @Test("Rejects a whitespace-only query")
    func rejectsWhitespaceOnlyQuery() {
        let client = PealimClient()

        #expect(throws: PealimClientError.emptyQuery) {
            try client.searchURL(for: " \n\t ")
        }
    }
}
