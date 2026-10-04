import Foundation

/// A dictionary entry returned by Pealim's word-form search.
public struct PealimSearchResult: Codable, Hashable, Identifiable, Sendable {
    public var id: String { sourceURL.absoluteString }

    /// The vocalized headword displayed by Pealim.
    public let lemma: String

    /// The pronunciation shown for the form that matched the search query.
    public let transcription: String?

    /// A display-ready root such as `ח - פ - שׂ`.
    public let root: String?

    /// Pealim's complete grammatical description, for example
    /// `глагол – ПИЭЛЬ` or `существительное – модель котель, мужской род`.
    public let partOfSpeech: String

    /// The Russian meaning exactly as presented in the search result.
    public let meaning: String

    public let sourceURL: URL
    public let audioURL: URL?

    public init(
        lemma: String,
        transcription: String? = nil,
        root: String? = nil,
        partOfSpeech: String,
        meaning: String,
        sourceURL: URL,
        audioURL: URL? = nil
    ) {
        self.lemma = lemma
        self.transcription = transcription
        self.root = root
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.sourceURL = sourceURL
        self.audioURL = audioURL
    }
}

public struct PealimSearchResponse: Codable, Equatable, Sendable {
    public let query: String
    public let results: [PealimSearchResult]

    public init(query: String, results: [PealimSearchResult]) {
        self.query = query
        self.results = results
    }
}
