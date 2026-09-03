import XCTest
@testable import JieJuLanguage

final class OpenAICompatibleTests: XCTestCase {
    func testCompletionBuildsAuthorizedOpenAICompatibleRequest() async throws {
        let response = """
        {"choices":[{"message":{"role":"assistant","content":"{\\"translation\\":\\"火车六点出发。\\",\\"sentenceCore\\":\\"The train leaves at six.\\",\\"grammarPoints\\":[],\\"keyPhrases\\":[]}"}}]}
        """
        let client = RecordingHTTPClient(response: .init(statusCode: 200, data: Data(response.utf8)))
        let ai = OpenAICompatibleReadingAI(
            baseURL: URL(string: "https://example.com/v1")!, apiKey: "secret-key", model: "cloud-model", client: client
        )

        let result = try await ai.explain(.init(targetText: "The train leaves at six."))

        XCTAssertEqual(result.translation, "火车六点出发。")
        let request = await client.lastRequest
        XCTAssertEqual(request?.url.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request?.headers["Authorization"], "Bearer secret-key")
        let body = try XCTUnwrap(request?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "cloud-model")
        XCTAssertEqual((object["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testMissingAPIKeyFailsBeforeNetworkRequest() async {
        let client = RecordingHTTPClient(response: .init(statusCode: 200, data: Data()))
        let ai = OpenAICompatibleReadingAI(
            baseURL: URL(string: "https://example.com/v1")!, apiKey: " ", model: "model", client: client
        )
        do {
            _ = try await ai.explain(.init(targetText: "Hello."))
            XCTFail("Expected validation error")
        } catch let error as ReadingAIError {
            XCTAssertEqual(error, .invalidInput("API Key 不能为空"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let request = await client.lastRequest
        XCTAssertNil(request)
    }

    func testCloudErrorMessageIsPreserved() async {
        let data = Data("{\"error\":{\"message\":\"invalid key\"}}".utf8)
        let client = RecordingHTTPClient(response: .init(statusCode: 401, data: data))
        let ai = OpenAICompatibleReadingAI(
            baseURL: URL(string: "https://example.com/v1")!, apiKey: "bad", model: "model", client: client
        )
        do {
            _ = try await ai.explain(.init(targetText: "Hello."))
            XCTFail("Expected service error")
        } catch let error as ReadingAIError {
            XCTAssertEqual(error, .serviceUnavailable("invalid key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamingChatCompletionPublishesPreviewAndValidatedFinalValue() async throws {
        let chunks = [
            "{\"translation\":\"火车六点出发。\",",
            "\"sentenceCore\":\"The train leaves at six.\",",
            "\"grammarPoints\":[],\"keyPhrases\":[]}"
        ]
        let lines = try chunks.map { content -> Data in
            let json = try JSONSerialization.data(withJSONObject: [
                "choices": [["delta": ["content": content]]]
            ])
            return Data("data: \(String(decoding: json, as: UTF8.self))".utf8)
        } + [Data("data: [DONE]".utf8)]
        let client = StreamingRecordingHTTPClient(lines: lines)
        let ai = OpenAICompatibleReadingAI(
            baseURL: URL(string: "https://example.com/v1")!, apiKey: "secret", model: "model", client: client
        )

        let stream = try await ai.explanationStream(.init(targetText: "The train leaves at six."))
        var values: [Explanation] = []
        for try await value in stream { values.append(value) }

        XCTAssertGreaterThanOrEqual(values.count, 2)
        XCTAssertEqual(values.first?.translation, "火车六点出发。")
        XCTAssertEqual(values.last?.sentenceCore, "The train leaves at six.")
    }
}

private actor RecordingHTTPClient: HTTPClient {
    let response: HTTPResponse
    private(set) var lastRequest: HTTPRequest?

    init(response: HTTPResponse) { self.response = response }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lastRequest = request
        return response
    }
}

private actor StreamingRecordingHTTPClient: StreamingHTTPClient {
    let lines: [Data]

    init(lines: [Data]) { self.lines = lines }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        XCTFail("A valid stream should not require a repair request")
        return .init(statusCode: 500, data: Data())
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPDataStream {
        let values = lines
        return HTTPDataStream(statusCode: 200, lines: AsyncThrowingStream<Data, Error> { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        })
    }
}
