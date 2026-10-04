import Foundation

/// Decodes the compact JSON representation returned by Pealim search when the
/// request advertises `Accept: application/json`.
public struct PealimJSONParser: Sendable {
    public init() {}

    public func parse(
        _ data: Data,
        documentURL: URL = PealimClient.defaultBaseURL
    ) throws -> [PealimSearchResult] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return (payload.hebrewWords + payload.russianWords).compactMap { entry in
            makeSearchResult(from: entry, documentURL: documentURL)
        }
    }

    private func makeSearchResult(from entry: Entry, documentURL: URL) -> PealimSearchResult? {
        let lemma = entry.lemma.hebrew.trimmed
        let meaning = entry.meaning.trimmed
        guard
            !lemma.isEmpty,
            !meaning.isEmpty,
            let sourceURL = URL(string: entry.link, relativeTo: documentURL)?.absoluteURL
        else {
            return nil
        }

        let root = entry.root?.trimmed.nilIfEmpty.flatMap { value in
            ["-", "–", "—"].contains(value) ? nil : value
        }
        let transcription = entry.lemma.transcription?
            .replacingOccurrences(of: "`", with: "'")
            .trimmed
            .nilIfEmpty

        return PealimSearchResult(
            lemma: lemma,
            transcription: transcription,
            root: root,
            partOfSpeech: Self.grammaticalDescription(for: entry),
            meaning: meaning,
            sourceURL: sourceURL,
            audioURL: nil
        )
    }

    private static func grammaticalDescription(for entry: Entry) -> String {
        let rawPartOfSpeech = entry.partOfSpeech.trimmed
        let partOfSpeech = partOfSpeechNames[rawPartOfSpeech.lowercased()] ?? rawPartOfSpeech
        var components = [partOfSpeech]

        if let rawBinyan = entry.binyan?.trimmed.nilIfEmpty {
            components.append(binyanNames[rawBinyan.lowercased()] ?? rawBinyan)
        }
        if let mishkal = entry.mishkal?.trimmed.nilIfEmpty {
            components.append("мишкаль \(mishkal)")
        }

        return components.filter { !$0.isEmpty }.joined(separator: " – ")
    }

    private static let partOfSpeechNames: [String: String] = [
        "verb": "глагол",
        "noun": "существительное",
        "adjective": "прилагательное",
        "adj": "прилагательное",
        "adverb": "наречие",
        "adv": "наречие",
        "preposition": "предлог",
        "pronoun": "местоимение",
        "numeral": "числительное",
        "conjunction": "союз",
        "interjection": "междометие",
        "particle": "частица",
        "proper-noun": "имя собственное",
        "proper noun": "имя собственное",
    ]

    /// Pealim uses compact linguistic stem codes in its JSON response.
    /// Aliases cover both the currently observed values and common passive
    /// spellings while unrecognized values remain visible to the caller.
    private static let binyanNames: [String: String] = [
        "g": "ПААЛЬ",
        "n": "НИФЪАЛЬ",
        "d": "ПИЭЛЬ",
        "dp": "ПУАЛЬ",
        "d-passive": "ПУАЛЬ",
        "h": "ХИФЪИЛЬ",
        "c": "ХИФЪИЛЬ",
        "hp": "ХУФЪАЛЬ",
        "cp": "ХУФЪАЛЬ",
        "h-passive": "ХУФЪАЛЬ",
        "c-passive": "ХУФЪАЛЬ",
        "dt": "ХИТПАЭЛЬ",
        "td": "ХИТПАЭЛЬ",
    ]
}

private extension PealimJSONParser {
    struct Payload: Decodable {
        let hebrewWords: [Entry]
        let russianWords: [Entry]

        enum CodingKeys: String, CodingKey {
            case hebrewWords = "he-words"
            case russianWords = "ru-words"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hebrewWords = try container.decodeIfPresent([Entry].self, forKey: .hebrewWords) ?? []
            russianWords = try container.decodeIfPresent([Entry].self, forKey: .russianWords) ?? []
        }
    }

    struct Entry: Decodable {
        let link: String
        let lemma: Lemma
        let root: String?
        let formKeys: [String]?
        let partOfSpeech: String
        let binyan: String?
        let mishkal: String?
        let meaning: String

        enum CodingKeys: String, CodingKey {
            case link
            case lemma
            case root
            case formKeys = "form-keys"
            case partOfSpeech = "part-of-speech"
            case binyan
            case mishkal
            case meaning
        }
    }

    struct Lemma: Decodable {
        let hebrew: String
        let transcription: String?

        enum CodingKeys: String, CodingKey {
            case hebrew = "he"
            case transcription = "tr"
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
