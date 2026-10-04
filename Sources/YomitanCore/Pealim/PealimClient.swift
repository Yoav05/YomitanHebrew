import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PealimClientError: Error, Equatable, LocalizedError {
    case emptyQuery
    case invalidSearchURL
    case invalidResponse
    case httpStatus(Int)
    case undecodableResponse

    public var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "The Pealim search query is empty."
        case .invalidSearchURL:
            return "The Pealim search URL could not be created."
        case .invalidResponse:
            return "Pealim returned a non-HTTP response."
        case let .httpStatus(statusCode):
            return "Pealim returned HTTP status \(statusCode)."
        case .undecodableResponse:
            return "The Pealim response could not be decoded."
        }
    }
}

/// Immutable and safe to share between tasks. `URLSession` is thread-safe and
/// both parser values are `Sendable`; the client itself keeps no mutable state.
public final class PealimClient: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://www.pealim.com/")!

    private let session: URLSession
    private let baseURL: URL
    private let jsonParser: PealimJSONParser
    private let parser: PealimHTMLParser

    public init(
        session: URLSession = .shared,
        baseURL: URL = PealimClient.defaultBaseURL,
        jsonParser: PealimJSONParser = PealimJSONParser(),
        parser: PealimHTMLParser = PealimHTMLParser()
    ) {
        self.session = session
        self.baseURL = baseURL
        self.jsonParser = jsonParser
        self.parser = parser
    }

    public func search(_ query: String) async throws -> PealimSearchResponse {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = try searchURL(for: normalizedQuery)

        var jsonRequest = URLRequest(url: url)
        jsonRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        jsonRequest.setValue("ru", forHTTPHeaderField: "Accept-Language")

        let (jsonData, jsonResponse) = try await session.data(for: jsonRequest)
        guard let jsonHTTPResponse = jsonResponse as? HTTPURLResponse else {
            throw PealimClientError.invalidResponse
        }

        if (200..<300).contains(jsonHTTPResponse.statusCode) {
            let documentURL = jsonHTTPResponse.url ?? url
            if let results = try? jsonParser.parse(jsonData, documentURL: documentURL) {
                return PealimSearchResponse(query: normalizedQuery, results: results)
            }

            // Some deployments may ignore the Accept header and return HTML.
            if
                let html = String(data: jsonData, encoding: .utf8),
                html.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
            {
                return PealimSearchResponse(
                    query: normalizedQuery,
                    results: parser.parse(html, documentURL: documentURL)
                )
            }
        } else if ![406, 415].contains(jsonHTTPResponse.statusCode) {
            throw PealimClientError.httpStatus(jsonHTTPResponse.statusCode)
        }

        // If JSON is unsupported or its contract changes, request the stable
        // HTML search page and use the isolated HTML parser as a fallback.
        var htmlRequest = URLRequest(url: url)
        htmlRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        htmlRequest.setValue("ru", forHTTPHeaderField: "Accept-Language")

        let (htmlData, htmlResponse) = try await session.data(for: htmlRequest)
        guard let htmlHTTPResponse = htmlResponse as? HTTPURLResponse else {
            throw PealimClientError.invalidResponse
        }
        guard (200..<300).contains(htmlHTTPResponse.statusCode) else {
            throw PealimClientError.httpStatus(htmlHTTPResponse.statusCode)
        }
        guard let html = String(data: htmlData, encoding: .utf8) else {
            throw PealimClientError.undecodableResponse
        }

        let documentURL = htmlHTTPResponse.url ?? url
        let results = parser.parse(html, documentURL: documentURL)
        return PealimSearchResponse(query: normalizedQuery, results: results)
    }

    /// Builds Pealim's Russian word-form search URL without making a request.
    public func searchURL(for query: String) throws -> URL {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw PealimClientError.emptyQuery
        }

        let endpoint = baseURL.appendingPathComponent("ru/search/")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: true) else {
            throw PealimClientError.invalidSearchURL
        }
        components.queryItems = [URLQueryItem(name: "q", value: normalizedQuery)]

        guard let url = components.url else {
            throw PealimClientError.invalidSearchURL
        }
        return url
    }
}
