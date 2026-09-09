import Foundation
import XCTest
@testable import JieJuLanguage

final class VocabularyAITests: XCTestCase {
    func testRequestAndExplanationRoundTripAndValidation() throws {
        let request = WordExplanationRequest(
            selectedText: "continued",
            sentenceContext: "She continued walking.",
            precedingContext: "It was raining.",
            sourceLanguage: "English",
            explanationLanguage: "Chinese"
        )
        XCTAssertEqual(try roundTrip(request), request)
        let requestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(requestObject["followingContext"], "Optional v4 fields are omitted when absent")

        let explanation = WordExplanation(
            surface: "continued", lemma: "continue", reading: nil, partOfSpeech: "verb",
            contextualMeaning: "继续", briefMeaning: "持续；继续",
            inflection: "continue 的过去式", collocations: [.init(text: "continue doing", meaning: "继续做")]
        )
        XCTAssertEqual(try roundTrip(explanation), explanation)
        let explanationObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(explanation)) as? [String: Any])
        XCTAssertNil(explanationObject["reading"], "Optional v4 fields are omitted when absent")
        XCTAssertNoThrow(try explanation.validated(against: request))
        XCTAssertThrowsError(try WordExplanation(
            surface: "walking", lemma: "walk", partOfSpeech: "verb",
            contextualMeaning: "走路", briefMeaning: "走路"
        ).validated(against: request))
    }

    func testPromptSeparatesSelectedTextFromContext() throws {
        let request = WordExplanationRequest(
            selectedText: "bank", sentenceContext: "She sat on the bank of the river.",
            precedingContext: "The bank approved his loan.", sourceLanguage: "English",
            explanationLanguage: "Chinese"
        )
        let payload = try XCTUnwrap(VocabularyPrompt.user(request).data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["selectedText"] as? String, "bank")
        XCTAssertEqual(object["sentenceContext"] as? String, "She sat on the bank of the river.")
        XCTAssertTrue(VocabularyPrompt.system.contains("Context may determine its meaning but is not the target"))
    }

    func testJapaneseLocalMorphologyOverridesModelIdentityFields() throws {
        let request = WordExplanationRequest(
            selectedText: "読みました", sentenceContext: "私は本を読みました。",
            sourceLanguage: "Japanese", explanationLanguage: "Chinese"
        )
        let model = WordExplanation(
            surface: "読みました", lemma: "模型猜错", reading: "もけい", partOfSpeech: "unknown",
            contextualMeaning: "读了", briefMeaning: "阅读", inflection: "模型内容"
        )
        let result = LocalVocabularyEnricher.enrich(model, request: request, morphology: MorphologyStub())
        XCTAssertEqual(result.surface, "読みました")
        XCTAssertEqual(result.lemma, "読む")
        XCTAssertEqual(result.reading, "よみました")
        XCTAssertEqual(result.partOfSpeech, "verb")
        XCTAssertEqual(result.inflection, "読みました → 読む")
        XCTAssertEqual(result.contextualMeaning, "读了")
    }

    func testOllamaRetriesOnceWhenResponseTargetsContextWord() async throws {
        let invalid = wordJSON(surface: "river")
        let valid = wordJSON(surface: "bank")
        let client = VocabularyHTTPStub(responses: [ollamaEnvelope(invalid), ollamaEnvelope(valid)])
        let provider = OllamaVocabularyAI(
            baseURL: URL(string: "http://127.0.0.1:11434")!, model: "model", client: client
        )
        let request = WordExplanationRequest(
            selectedText: "bank", sentenceContext: "She sat on the bank of the river."
        )

        let result = try await provider.explainWord(request)

        XCTAssertEqual(result.surface, "bank")
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testOllamaStreamPublishesMeaningBeforeValidatedFinalValue() async throws {
        let chunks = [
            "{\"surface\":\"bank\",\"lemma\":\"bank\",\"reading\":\"\",\"partOfSpeech\":\"noun\",",
            "\"contextualMeaning\":\"河岸\",\"briefMeaning\":\"岸；银行\",",
            "\"inflection\":\"\",\"collocations\":[]}"
        ]
        let lines = chunks.map { Data("{\"message\":{\"role\":\"assistant\",\"content\":\"\($0.jsonEscaped)\"}}".utf8) }
        let client = VocabularyStreamingStub(lines: lines)
        let provider = OllamaVocabularyAI(
            baseURL: URL(string: "http://127.0.0.1:11434")!, model: "model", client: client
        )
        let request = WordExplanationRequest(selectedText: "bank", sentenceContext: "the bank of the river")

        var values: [WordExplanation] = []
        for try await value in try await provider.wordExplanationStream(request) { values.append(value) }

        XCTAssertGreaterThanOrEqual(values.count, 2)
        XCTAssertEqual(values.first?.contextualMeaning, "河岸")
        XCTAssertEqual(values.last?.briefMeaning, "岸；银行")
    }

    func testMalformedResponseFailsAfterSingleRepair() async {
        let client = VocabularyHTTPStub(responses: [ollamaEnvelope("{}"), ollamaEnvelope("{}")])
        let provider = OllamaVocabularyAI(
            baseURL: URL(string: "http://127.0.0.1:11434")!, model: "model", client: client
        )
        do {
            _ = try await provider.explainWord(.init(selectedText: "bank", sentenceContext: "a bank"))
            XCTFail("Expected decoding failure")
        } catch {
            let requestCount = await client.requestCount
            XCTAssertEqual(requestCount, 2)
        }
    }

    func testOpenAICompatibleRequestUsesAuthorizationAndWordSchema() async throws {
        let content = wordJSON(surface: "bank")
        let envelope = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["role": "assistant", "content": content]]]
        ])
        let client = VocabularyHTTPStub(responses: [.init(statusCode: 200, data: envelope)])
        let provider = OpenAICompatibleVocabularyAI(
            baseURL: URL(string: "https://example.com/v1")!, apiKey: "secret", model: "cloud-model", client: client
        )

        let result = try await provider.explainWord(.init(selectedText: "bank", sentenceContext: "the bank of the river"))

        XCTAssertEqual(result.contextualMeaning, "河岸")
        let request = await client.lastRequest
        XCTAssertEqual(request?.url.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertEqual(request?.headers["Authorization"], "Bearer secret")
        let body = try XCTUnwrap(request?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["model"] as? String, "cloud-model")
        XCTAssertEqual((object["response_format"] as? [String: String])?["type"], "json_object")
    }

    func testStoppingWordStreamCancelsTransportWithoutRepairRequest() async throws {
        let client = CancellationVocabularyStreamingStub()
        let provider = OllamaVocabularyAI(
            baseURL: URL(string: "http://127.0.0.1:11434")!, model: "model", client: client
        )
        let stream = try await provider.wordExplanationStream(
            .init(selectedText: "bank", sentenceContext: "the bank of the river")
        )

        for try await _ in stream { break }
        try await Task.sleep(for: .milliseconds(100))

        let sendCount = await client.sendCount
        XCTAssertEqual(sendCount, 0, "Cancellation must not trigger a repair request")
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func wordJSON(surface: String) -> String {
        """
        {"surface":"\(surface)","lemma":"\(surface)","reading":"","partOfSpeech":"noun","contextualMeaning":"河岸","briefMeaning":"岸；银行","inflection":"","collocations":[]}
        """
    }

    private func ollamaEnvelope(_ content: String) -> HTTPResponse {
        let data = try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
        return .init(statusCode: 200, data: data)
    }
}

private struct MorphologyStub: JapaneseMorphologyProviding {
    func segments(for text: String) -> [ReadingSegment] { [.init(surface: text, reading: "よみました")] }
    func tokens(for text: String) -> [JapaneseMorphologicalToken] {
        [.init(surface: "読みました", reading: "よみました", dictionaryForm: "読む", partOfSpeech: "verb", isInflected: true)]
    }
}

private actor VocabularyHTTPStub: HTTPClient {
    private var responses: [HTTPResponse]
    private(set) var requestCount = 0
    private(set) var lastRequest: HTTPRequest?

    init(responses: [HTTPResponse]) { self.responses = responses }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestCount += 1
        lastRequest = request
        return responses.removeFirst()
    }
}

private actor CancellationVocabularyStreamingStub: StreamingHTTPClient {
    private(set) var sendCount = 0

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        sendCount += 1
        return .init(statusCode: 500, data: Data())
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPDataStream {
        let firstChunk = Data("{\"message\":{\"role\":\"assistant\",\"content\":\"{\\\"surface\\\":\\\"bank\\\",\\\"lemma\\\":\\\"bank\\\",\\\"reading\\\":\\\"\\\",\\\"partOfSpeech\\\":\\\"noun\\\",\\\"contextualMeaning\\\":\\\"河岸\\\"}\"}}".utf8)
        return .init(statusCode: 200, lines: AsyncThrowingStream { continuation in
            continuation.yield(firstChunk)
        })
    }
}

private actor VocabularyStreamingStub: StreamingHTTPClient {
    let lines: [Data]
    init(lines: [Data]) { self.lines = lines }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        XCTFail("Valid stream should not use repair")
        return .init(statusCode: 500, data: Data())
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPDataStream {
        let lines = lines
        let stream = AsyncThrowingStream<Data, any Error>(Data.self) { continuation in
            for value in lines { continuation.yield(value) }
            continuation.finish()
        }
        return .init(statusCode: 200, lines: stream)
    }
}

private extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
