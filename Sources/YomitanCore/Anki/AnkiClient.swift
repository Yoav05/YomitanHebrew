import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AnkiClientError: Error, Equatable, Sendable, LocalizedError {
    case transport(String)
    case nonHTTPResponse
    case httpStatus(code: Int, body: String?)
    case api(String)
    case encoding(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case let .transport(message):
            return "Could not reach AnkiConnect: \(message)"
        case .nonHTTPResponse:
            return "AnkiConnect returned a non-HTTP response."
        case let .httpStatus(code, body):
            if let body, !body.isEmpty {
                return "AnkiConnect returned HTTP status \(code): \(body)"
            }
            return "AnkiConnect returned HTTP status \(code)."
        case let .api(message):
            return "AnkiConnect reported an API error: \(message)"
        case let .encoding(message):
            return "Could not encode the AnkiConnect request: \(message)"
        case let .decoding(message):
            return "Could not decode the AnkiConnect response: \(message)"
        }
    }
}

/// A small, concurrency-safe client for the AnkiConnect v6 local HTTP API.
public actor AnkiClient {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:8765")!
    public static let apiVersion = 6

    private let session: URLSession
    private let endpoint: URL
    private let apiKey: String?

    public init(
        endpoint: URL = AnkiClient.defaultEndpoint,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public func version() async throws -> Int {
        try await invoke(action: "version", params: EmptyParameters())
    }

    public func deckNames() async throws -> [String] {
        try await invoke(action: "deckNames", params: EmptyParameters())
    }

    public func modelNames() async throws -> [String] {
        try await invoke(action: "modelNames", params: EmptyParameters())
    }

    public func modelFieldNames(_ modelName: String) async throws -> [String] {
        try await invoke(
            action: "modelFieldNames",
            params: ModelFieldNamesParameters(modelName: modelName)
        )
    }

    @discardableResult
    public func createDeck(_ deckName: String) async throws -> AnkiDeckID {
        try await invoke(
            action: "createDeck",
            params: CreateDeckParameters(deck: deckName)
        )
    }

    @discardableResult
    public func createModel(_ model: AnkiModelDraft) async throws -> AnkiModelID {
        let createdModel: CreatedModelResponse = try await invoke(
            action: "createModel",
            params: model
        )
        return createdModel.id
    }

    @discardableResult
    public func addNote(_ note: AnkiNote) async throws -> AnkiNoteID {
        try await invoke(
            action: "addNote",
            params: NoteParameters(note: note)
        )
    }

    @discardableResult
    public func guiAddCards(_ note: AnkiNote) async throws -> AnkiNoteID {
        try await invoke(
            action: "guiAddCards",
            params: NoteParameters(note: note)
        )
    }

    private func invoke<Result, Parameters>(
        action: String,
        params: Parameters
    ) async throws -> Result
    where Result: Decodable & Sendable, Parameters: Encodable & Sendable {
        let payload = AnkiRequest(
            action: action,
            version: Self.apiVersion,
            params: params,
            key: apiKey
        )

        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            body = try encoder.encode(payload)
        } catch {
            throw AnkiClientError.encoding(Self.describe(error))
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AnkiClientError.transport(Self.describe(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnkiClientError.nonHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let responseBody = data.isEmpty
                ? nil
                : String(decoding: data.prefix(4_096), as: UTF8.self)
            throw AnkiClientError.httpStatus(
                code: httpResponse.statusCode,
                body: responseBody
            )
        }

        let decoder = JSONDecoder()
        do {
            let errorEnvelope = try decoder.decode(AnkiErrorEnvelope.self, from: data)
            if let apiError = errorEnvelope.error {
                throw AnkiClientError.api(apiError)
            }

            let envelope = try decoder.decode(AnkiResultEnvelope<Result>.self, from: data)
            guard let result = envelope.result else {
                throw AnkiClientError.decoding("The response did not contain a result.")
            }
            return result
        } catch let error as AnkiClientError {
            throw error
        } catch {
            throw AnkiClientError.decoding(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case let .dataCorrupted(context):
                return context.debugDescription
            case let .keyNotFound(key, context):
                return "Missing key \(key.stringValue): \(context.debugDescription)"
            case let .typeMismatch(type, context):
                return "Expected \(type): \(context.debugDescription)"
            case let .valueNotFound(type, context):
                return "Missing \(type): \(context.debugDescription)"
            @unknown default:
                return decodingError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

private struct EmptyParameters: Encodable, Sendable {}

private struct ModelFieldNamesParameters: Encodable, Sendable {
    let modelName: String
}

private struct CreateDeckParameters: Encodable, Sendable {
    let deck: String
}

private struct NoteParameters: Encodable, Sendable {
    let note: AnkiNote
}

private struct CreatedModelResponse: Decodable, Sendable {
    let id: AnkiModelID

    private enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericID = try? container.decode(AnkiModelID.self, forKey: .id) {
            id = numericID
            return
        }
        let stringID = try container.decode(String.self, forKey: .id)
        guard let numericID = AnkiModelID(stringID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "The created model ID is not a 64-bit integer."
            )
        }
        id = numericID
    }
}

private struct AnkiRequest<Parameters>: Encodable, Sendable
where Parameters: Encodable & Sendable {
    let action: String
    let version: Int
    let params: Parameters
    let key: String?
}

private struct AnkiErrorEnvelope: Decodable, Sendable {
    let error: String?
}

private struct AnkiResultEnvelope<Result>: Decodable, Sendable
where Result: Decodable & Sendable {
    let result: Result?
}
