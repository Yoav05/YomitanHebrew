import Foundation
import Testing
@testable import YomitanCore

@Suite("Pealim JSON parser")
struct PealimJSONParserTests {
    @Test("Parses both result groups in Hebrew-then-Russian order")
    func parsesBothResultGroups() throws {
        let data = try fixtureData()
        let documentURL = try #require(URL(string: "https://www.pealim.com/ru/search/?q=לחפש"))

        let results = try PealimJSONParser().parse(data, documentURL: documentURL)

        #expect(results.map(\.lemma) == ["לְחַפֵּשׂ", "אָב", "מִלָּה"])

        let verb = try #require(results.first)
        #expect(verb.transcription == "лехап'ес")
        #expect(verb.root == "ח - פ - שׂ")
        #expect(verb.partOfSpeech == "глагол – ПИЭЛЬ")
        #expect(verb.meaning == "искать")
        #expect(verb.sourceURL.absoluteString == "https://www.pealim.com/ru/dict/663-lechapes/")
        #expect(verb.audioURL == nil)

        let noun = results[1]
        #expect(noun.root == nil)
        #expect(noun.partOfSpeech == "существительное – мишкаль qotel-s")

        let unknownCodes = results[2]
        #expect(unknownCodes.partOfSpeech == "custom-pos – X")
    }

    @Test("Missing result groups decode as empty arrays")
    func missingGroupsAreEmpty() throws {
        let data = Data(#"{"he-words":[]}"#.utf8)

        let results = try PealimJSONParser().parse(data)

        #expect(results.isEmpty)
    }

    private func fixtureData() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "pealim-search", withExtension: "json"))
        return try Data(contentsOf: url)
    }
}
