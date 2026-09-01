import Foundation
import Testing
@testable import JieJuLanguage

actor StubHTTPClient: HTTPClient {
    private var responses: [Result<HTTPResponse, Error>]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [Result<HTTPResponse, Error>]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw ReadingAIError.transport("no stub response") }
        return try responses.removeFirst().get()
    }
}

@Suite struct OllamaTests {
    @Test func healthModelsAndExistence() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:0.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(tags), .success(tags)])
        let provider = OllamaReadingAI(client: client)
        #expect(try await provider.isHealthy())
        #expect(try await provider.models() == [.init(name: "qwen2.5:0.5b-instruct")])
        #expect(try await provider.hasModel())
    }

    @Test func reportsServiceAndModelErrors() async {
        let unavailable = OllamaReadingAI(client: StubHTTPClient([.success(response(503, "no"))]))
        await #expect(throws: ReadingAIError.self) { try await unavailable.models() }

        let missing = OllamaReadingAI(client: StubHTTPClient([.success(response(200, #"{"models":[]}"#))]))
        await #expect(throws: ReadingAIError.modelMissing("qwen2.5:0.5b-instruct")) {
            try await missing.explain(.init(targetText: "Hello"))
        }
    }

    @Test func mapsTransportAndTimeoutErrors() async {
        let timeout = OllamaReadingAI(client: StubHTTPClient([.failure(ReadingAIError.timeout)]))
        await #expect(throws: ReadingAIError.timeout) { try await timeout.models() }
        let transport = OllamaReadingAI(client: StubHTTPClient([.failure(ReadingAIError.transport("offline"))]))
        await #expect(throws: ReadingAIError.transport("offline")) { try await transport.models() }
    }

    @Test func explainsUsingStrictJSON() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:0.5b-instruct"}]}"#)
        let envelope = chatEnvelope(validJSON)
        let client = StubHTTPClient([.success(tags), .success(envelope)])
        let result = try await OllamaReadingAI(client: client).explain(.init(targetText: "Although tired, she continued."))
        #expect(result == sampleExplanation)
        let requests = await client.requests
        #expect(requests.last?.method == "POST")
        #expect(requests.last?.headers["Content-Type"] == "application/json")
    }

    @Test func retriesExactlyOnceAfterInvalidJSON() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:0.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("not json")), .success(chatEnvelope(validJSON))])
        let result = try await OllamaReadingAI(client: client).explain(.init(targetText: "Hello"))
        #expect(result == sampleExplanation)
        #expect(await client.requests.count == 3)
    }

    @Test func failsAfterOneRetry() async {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:0.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("bad")), .success(chatEnvelope("still bad"))])
        await #expect(throws: ReadingAIError.self) {
            try await OllamaReadingAI(client: client).explain(.init(targetText: "Hello"))
        }
        #expect(await client.requests.count == 3)
    }

    @Test func batchAttemptPreservesInvalidRawAfterRetry() async {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:0.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("bad")), .success(chatEnvelope("still bad"))])
        let attempt = await OllamaReadingAI(client: client).attemptExplanation(.init(targetText: "Hello"))
        #expect(!attempt.jsonValid)
        #expect(attempt.explanation == nil)
        #expect(attempt.raw == "still bad")
        #expect(attempt.error?.contains("Invalid model response") == true)
    }
}

private func response(_ status: Int, _ string: String) -> HTTPResponse { .init(statusCode: status, data: Data(string.utf8)) }
private func chatEnvelope(_ content: String) -> HTTPResponse {
    let data = try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
    return .init(statusCode: 200, data: data)
}
private var validJSON: String { String(decoding: try! JSONEncoder().encode(sampleExplanation), as: UTF8.self) }
