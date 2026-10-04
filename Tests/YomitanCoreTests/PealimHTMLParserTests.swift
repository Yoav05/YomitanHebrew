import Foundation
import Testing
@testable import YomitanCore

@Suite("Pealim HTML parser")
struct PealimHTMLParserTests {
    @Test("Parses a realistic Pealim result card")
    func parsesRealisticSearchResult() throws {
        let html = try fixture(named: "pealim-search", extension: "html")
        let documentURL = try #require(URL(string: "https://www.pealim.com/ru/search/?q=לחפש"))

        let results = PealimHTMLParser().parse(html, documentURL: documentURL)

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.lemma == "לְחַפֵּשׂ")
        #expect(result.transcription == "лехапес")
        #expect(result.root == "ח - פ - שׂ")
        #expect(result.partOfSpeech == "глагол – ПИЭЛЬ")
        #expect(result.meaning == "искать & разыскивать")
        #expect(result.sourceURL.absoluteString == "https://www.pealim.com/ru/dict/663-lechapes/")
        #expect(result.audioURL?.absoluteString == "https://audio.pealim.com/v0/1u/1ua8727rbx27m.mp3")
    }

    @Test("Skips a malformed card without discarding valid cards")
    func skipsMalformedCardWithoutDiscardingValidCard() throws {
        let validHTML = try fixture(named: "pealim-search", extension: "html")
        let malformedCard = """
        <div class="verb-search-result">
          <div class="verb-search-data">
            <div class="verb-search-lemma"><span class="menukad">חסר</span></div>
          </div>
        </div>
        """

        let results = PealimHTMLParser().parse(malformedCard + validHTML)

        #expect(results.map(\.lemma) == ["לְחַפֵּשׂ"])
    }

    private func fixture(named name: String, extension fileExtension: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: fileExtension))
        return try String(contentsOf: url, encoding: .utf8)
    }
}
