import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Testing
@testable import YomitanCore

@Suite("AnkiConnect client")
struct AnkiClientTests {
    @Test("Version sends a v6 JSON request and decodes the result")
    func versionRequest() async throws {
        #expect(AnkiClient.defaultEndpoint.absoluteString == "http://127.0.0.1:8765")

        let endpoint = makeEndpoint()
        let capturedRequest = LockedBox<RecordedRequest?>(nil)
        StubURLProtocol.register(endpoint: endpoint) { request in
            capturedRequest.set(try record(request))
            return try jsonResponse(for: request, body: #"{"result":6,"error":null}"#)
        }

        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())
        let version = try await client.version()

        #expect(version == 6)
        let request = try #require(capturedRequest.value)
        #expect(request.httpMethod == "POST")
        #expect(request.contentType == "application/json")

        let payload = try jsonObject(request.body)
        #expect(payload["action"] as? String == "version")
        #expect(payload["version"] as? Int == 6)
        #expect((payload["params"] as? [String: Any])?.count == 0)
        #expect(payload["key"] == nil)
    }

    @Test("Catalog, deck, and model methods map actions and parameters")
    func catalogAndProvisioningRequests() async throws {
        let endpoint = makeEndpoint()
        let requestBodies = LockedBox<[Data]>([])
        StubURLProtocol.register(endpoint: endpoint) { request in
            let body = try requestBodyData(request)
            requestBodies.mutate { $0.append(body) }
            let payload = try jsonObject(body)

            switch payload["action"] as? String {
            case "deckNames":
                return try jsonResponse(
                    for: request,
                    body: #"{"result":["Default","Hebrew"],"error":null}"#
                )
            case "modelNames":
                return try jsonResponse(
                    for: request,
                    body: #"{"result":["Basic","Hebrew Pealim"],"error":null}"#
                )
            case "modelFieldNames":
                return try jsonResponse(
                    for: request,
                    body: #"{"result":["EntryKey","Hebrew","Russian"],"error":null}"#
                )
            case "createDeck":
                return try jsonResponse(
                    for: request,
                    body: #"{"result":1519323742721,"error":null}"#
                )
            case "createModel":
                return try jsonResponse(
                    for: request,
                    body: #"{"result":{"id":"1551462107104","name":"Hebrew Pealim"},"error":null}"#
                )
            default:
                throw StubError.unexpectedRequest
            }
        }

        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        #expect(try await client.deckNames() == ["Default", "Hebrew"])
        #expect(try await client.modelNames() == ["Basic", "Hebrew Pealim"])
        #expect(
            try await client.modelFieldNames("Hebrew Pealim")
                == ["EntryKey", "Hebrew", "Russian"]
        )
        #expect(try await client.createDeck("Hebrew::Pealim") == 1_519_323_742_721)

        let model = AnkiModelDraft(
            modelName: "Hebrew Pealim",
            inOrderFields: ["EntryKey", "Hebrew", "Russian"],
            css: ".hebrew { direction: rtl; }",
            cardTemplates: [
                AnkiCardTemplateDraft(
                    name: "Recognition",
                    front: "{{Hebrew}}",
                    back: "{{Russian}}"
                ),
            ]
        )
        #expect(try await client.createModel(model) == 1_551_462_107_104)

        let payloads = try requestBodies.value.map(jsonObject)
        #expect(payloads.map { $0["action"] as? String } == [
            "deckNames",
            "modelNames",
            "modelFieldNames",
            "createDeck",
            "createModel",
        ])
        #expect(
            (payloads[2]["params"] as? [String: Any])?["modelName"] as? String
                == "Hebrew Pealim"
        )
        #expect(
            (payloads[3]["params"] as? [String: Any])?["deck"] as? String
                == "Hebrew::Pealim"
        )

        let modelParameters = try #require(payloads[4]["params"] as? [String: Any])
        #expect(modelParameters["modelName"] as? String == "Hebrew Pealim")
        #expect(
            modelParameters["inOrderFields"] as? [String]
                == ["EntryKey", "Hebrew", "Russian"]
        )
        #expect(modelParameters["css"] as? String == ".hebrew { direction: rtl; }")
        #expect(modelParameters["isCloze"] as? Bool == false)
        let templates = try #require(modelParameters["cardTemplates"] as? [[String: Any]])
        #expect(templates.first?["Name"] as? String == "Recognition")
        #expect(templates.first?["Front"] as? String == "{{Hebrew}}")
        #expect(templates.first?["Back"] as? String == "{{Russian}}")
    }

    @Test("Add note sends an API key and arbitrary fields")
    func addNoteRequest() async throws {
        let endpoint = makeEndpoint()
        let capturedRequest = LockedBox<RecordedRequest?>(nil)
        StubURLProtocol.register(endpoint: endpoint) { request in
            capturedRequest.set(try record(request))
            return try jsonResponse(
                for: request,
                body: #"{"result":1496198395707,"error":null}"#
            )
        }

        let card = AnkiCardDraft(
            fields: [
                "EntryKey": "pealim:663",
                "Hebrew": "לְחַפֵּשׂ",
                "Russian": "искать",
                "Custom Field": "custom value",
            ],
            tags: ["hebrew", "pealim"]
        )
        let note = AnkiNote(
            deckName: "Hebrew::Pealim",
            modelName: "Hebrew Pealim",
            fields: card.fields,
            tags: card.tags,
            allowDuplicate: false
        )
        let client = AnkiClient(
            endpoint: endpoint,
            apiKey: "test-secret",
            session: makeStubSession()
        )

        let noteID = try await client.addNote(note)

        #expect(noteID == 1_496_198_395_707)
        #expect(note.card == card)

        let request = try #require(capturedRequest.value)
        let payload = try jsonObject(request.body)
        #expect(payload["action"] as? String == "addNote")
        #expect(payload["key"] as? String == "test-secret")

        let params = try #require(payload["params"] as? [String: Any])
        let encodedNote = try #require(params["note"] as? [String: Any])
        #expect(encodedNote["deckName"] as? String == "Hebrew::Pealim")
        #expect(encodedNote["modelName"] as? String == "Hebrew Pealim")
        #expect(encodedNote["fields"] as? [String: String] == card.fields)
        #expect(encodedNote["tags"] as? [String] == card.tags)
        #expect(
            (encodedNote["options"] as? [String: Any])?["allowDuplicate"] as? Bool
                == false
        )
    }

    @Test("GUI add cards uses the graphical action")
    func guiAddCardsRequest() async throws {
        let endpoint = makeEndpoint()
        let capturedRequest = LockedBox<RecordedRequest?>(nil)
        StubURLProtocol.register(endpoint: endpoint) { request in
            capturedRequest.set(try record(request))
            return try jsonResponse(for: request, body: #"{"result":42,"error":null}"#)
        }

        let note = AnkiNote(
            deckName: "Hebrew",
            modelName: "Basic",
            fields: ["Front": "שלום", "Back": "привет"],
            options: AnkiNoteOptions(closeAfterAdding: true)
        )
        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        #expect(try await client.guiAddCards(note) == 42)

        let request = try #require(capturedRequest.value)
        let payload = try jsonObject(request.body)
        #expect(payload["action"] as? String == "guiAddCards")
        let params = try #require(payload["params"] as? [String: Any])
        let encodedNote = try #require(params["note"] as? [String: Any])
        #expect(
            (encodedNote["options"] as? [String: Any])?["closeAfterAdding"] as? Bool
                == true
        )
    }

    @Test("Transport failures are typed")
    func transportFailure() async {
        let endpoint = makeEndpoint()
        StubURLProtocol.register(endpoint: endpoint) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        do {
            _ = try await client.version()
            Issue.record("Expected a transport error")
        } catch let error as AnkiClientError {
            guard case let .transport(message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(!message.isEmpty)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("HTTP failures include status and response body")
    func httpFailure() async {
        let endpoint = makeEndpoint()
        StubURLProtocol.register(endpoint: endpoint) { request in
            try jsonResponse(for: request, statusCode: 503, body: "Anki is busy")
        }
        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        do {
            _ = try await client.version()
            Issue.record("Expected an HTTP error")
        } catch let error as AnkiClientError {
            #expect(error == .httpStatus(code: 503, body: "Anki is busy"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("API failures are typed")
    func apiFailure() async {
        let endpoint = makeEndpoint()
        StubURLProtocol.register(endpoint: endpoint) { request in
            try jsonResponse(
                for: request,
                body: #"{"result":null,"error":"model was not found"}"#
            )
        }
        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        do {
            _ = try await client.version()
            Issue.record("Expected an API error")
        } catch let error as AnkiClientError {
            #expect(error == .api("model was not found"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Malformed successful responses are decode failures")
    func decodeFailure() async {
        let endpoint = makeEndpoint()
        StubURLProtocol.register(endpoint: endpoint) { request in
            try jsonResponse(for: request, body: #"{"result":"six","error":null}"#)
        }
        let client = AnkiClient(endpoint: endpoint, session: makeStubSession())

        do {
            _ = try await client.version()
            Issue.record("Expected a decoding error")
        } catch let error as AnkiClientError {
            guard case let .decoding(message) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(!message.isEmpty)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

private enum StubError: Error {
    case missingHandler
    case invalidResponse
    case malformedRequest
    case unexpectedRequest
}

private struct RecordedRequest: Sendable {
    let httpMethod: String?
    let contentType: String?
    let body: Data
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func mutate(_ mutation: (inout Value) -> Void) {
        lock.lock()
        mutation(&storage)
        lock.unlock()
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let handlers = LockedBox<[String: Handler]>([:])

    static func register(endpoint: URL, handler: @escaping Handler) {
        handlers.mutate { $0[endpoint.absoluteString] = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return handlers.value[url.absoluteString] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let url = request.url,
            let handler = Self.handlers.value[url.absoluteString]
        else {
            client?.urlProtocol(self, didFailWithError: StubError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeEndpoint() -> URL {
    URL(string: "http://127.0.0.1:8765/\(UUID().uuidString)")!
}

private func jsonResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    body: String
) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url else {
        throw StubError.invalidResponse
    }
    guard let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
    ) else {
        throw StubError.invalidResponse
    }
    return (response, Data(body.utf8))
}

private func record(_ request: URLRequest) throws -> RecordedRequest {
    RecordedRequest(
        httpMethod: request.httpMethod,
        contentType: request.value(forHTTPHeaderField: "Content-Type"),
        body: try requestBodyData(request)
    )
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        throw StubError.malformedRequest
    }

    stream.open()
    defer { stream.close() }

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
    defer { buffer.deallocate() }

    var data = Data()
    while true {
        let count = stream.read(buffer, maxLength: 4_096)
        if count < 0 {
            throw stream.streamError ?? StubError.malformedRequest
        }
        if count == 0 {
            return data
        }
        data.append(buffer, count: count)
    }
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = object as? [String: Any] else {
        throw StubError.malformedRequest
    }
    return dictionary
}
