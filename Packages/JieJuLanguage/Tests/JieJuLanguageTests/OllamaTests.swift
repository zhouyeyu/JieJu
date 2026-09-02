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

actor StubStreamingHTTPClient: StreamingHTTPClient {
    private let tags: HTTPResponse
    private let streamLines: [Data]
    private(set) var requests: [HTTPRequest] = []

    init(tags: HTTPResponse, streamLines: [Data]) {
        self.tags = tags
        self.streamLines = streamLines
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return tags
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPDataStream {
        requests.append(request)
        let lines = streamLines
        return HTTPDataStream(statusCode: 200, lines: AsyncThrowingStream<Data, Error>(bufferingPolicy: .unbounded) { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        })
    }
}

@Suite struct OllamaTests {
    @Test func healthModelsAndExistence() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(tags), .success(tags)])
        let provider = OllamaReadingAI(client: client)
        #expect(try await provider.isHealthy())
        #expect(try await provider.models() == [.init(name: "qwen2.5:1.5b-instruct")])
        #expect(try await provider.hasModel())
    }

    @Test func reportsServiceAndModelErrors() async {
        let unavailable = OllamaReadingAI(client: StubHTTPClient([.success(response(503, "no"))]))
        await #expect(throws: ReadingAIError.self) { try await unavailable.models() }

        let missing = OllamaReadingAI(client: StubHTTPClient([.success(response(200, #"{"models":[]}"#))]))
        await #expect(throws: ReadingAIError.modelMissing("qwen2.5:1.5b-instruct")) {
            try await missing.explain(.init(targetText: "Hello"))
        }
    }

    @Test func diagnosisDistinguishesReadyMissingAndOffline() async {
        let readyTags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"},{"name":"other:latest"}]}"#)
        let ready = await OllamaReadingAI(client: StubHTTPClient([.success(readyTags)])).diagnose()
        #expect(ready == .ready(model: "qwen2.5:1.5b-instruct", installedModelCount: 2))

        let missingTags = response(200, #"{"models":[{"name":"other:latest"}]}"#)
        let missing = await OllamaReadingAI(client: StubHTTPClient([.success(missingTags)])).diagnose()
        #expect(missing == .modelMissing(required: "qwen2.5:1.5b-instruct", installedModels: ["other:latest"]))

        let offline = await OllamaReadingAI(client: StubHTTPClient([.failure(ReadingAIError.transport("offline"))])).diagnose()
        guard case .serviceUnavailable(let message) = offline else {
            Issue.record("Expected unavailable diagnostic")
            return
        }
        #expect(message.contains("offline"))
    }

    @Test func mapsTransportAndTimeoutErrors() async {
        let timeout = OllamaReadingAI(client: StubHTTPClient([.failure(ReadingAIError.timeout)]))
        await #expect(throws: ReadingAIError.timeout) { try await timeout.models() }
        let transport = OllamaReadingAI(client: StubHTTPClient([.failure(ReadingAIError.transport("offline"))]))
        await #expect(throws: ReadingAIError.transport("offline")) { try await transport.models() }
    }

    @Test func explainsUsingStrictJSON() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let envelope = chatEnvelope(validJSON)
        let client = StubHTTPClient([.success(tags), .success(envelope)])
        let result = try await OllamaReadingAI(client: client).explain(.init(targetText: "Although tired, she continued."))
        #expect(result == sampleExplanation)
        let requests = await client.requests
        #expect(requests.last?.method == "POST")
        #expect(requests.last?.headers["Content-Type"] == "application/json")
        let requestBody = try #require(requests.last?.body)
        let bodyJSON = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let options = try #require(bodyJSON["options"] as? [String: Any])
        #expect(options["temperature"] as? Double == 0)
        #expect(options["num_predict"] as? Int == 350)
        let format = try #require(bodyJSON["format"] as? [String: Any])
        let required = try #require(format["required"] as? [String])
        #expect(Set(required) == Set(["translation", "sentenceCore", "grammarPoints", "keyPhrases"]))
        let properties = try #require(format["properties"] as? [String: Any])
        let translation = try #require(properties["translation"] as? [String: Any])
        let translationDescription = try #require(translation["description"] as? String)
        #expect(translationDescription.localizedCaseInsensitiveContains("Chinese"))
        #expect(translationDescription.localizedCaseInsensitiveContains("never in English"))
        let sentenceCore = try #require(properties["sentenceCore"] as? [String: Any])
        let coreDescription = try #require(sentenceCore["description"] as? String)
        #expect(coreDescription.localizedCaseInsensitiveContains("English"))
    }

    @Test func schemaCarriesRequestLanguages() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope(validJSON))])
        let request = ExplanationRequest(
            targetText: "Although tired, she continued.",
            sourceLanguage: "German", explanationLanguage: "Japanese"
        )
        _ = try await OllamaReadingAI(client: client).explain(request)
        let body = try #require((await client.requests).last?.body)
        let bodyJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try #require(bodyJSON["format"] as? [String: Any])
        let properties = try #require(format["properties"] as? [String: Any])
        let translation = try #require(properties["translation"] as? [String: Any])
        let translationDescription = try #require(translation["description"] as? String)
        #expect(translationDescription.localizedCaseInsensitiveContains("Japanese"))
        let sentenceCore = try #require(properties["sentenceCore"] as? [String: Any])
        let coreDescription = try #require(sentenceCore["description"] as? String)
        #expect(coreDescription.localizedCaseInsensitiveContains("German"))
    }

    @Test func retriesExactlyOnceAfterInvalidJSON() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("not json")), .success(chatEnvelope(validJSON))])
        let result = try await OllamaReadingAI(client: client).explain(.init(targetText: "Although tired, she continued."))
        #expect(result == sampleExplanation)
        #expect(await client.requests.count == 3)
    }

    @Test func retriesWhenValidJSONReferencesContextInsteadOfTarget() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let offTarget = Explanation(
            translation: "虽然很累，她仍继续前行。",
            sentenceCore: "she continued",
            grammarPoints: [],
            keyPhrases: [.init(text: "went home", meaning: "回家")]
        )
        let offTargetJSON = String(decoding: try JSONEncoder().encode(offTarget), as: UTF8.self)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope(offTargetJSON)), .success(chatEnvelope(validJSON))])
        let request = ExplanationRequest(targetText: "Although tired, she continued.", precedingContext: "Her friends went home.")

        let result = try await OllamaReadingAI(client: client).explain(request)

        #expect(result == sampleExplanation)
        let requests = await client.requests
        #expect(requests.count == 3)
        let repairBody = try #require(requests.last?.body)
        let bodyJSON = try #require(JSONSerialization.jsonObject(with: repairBody) as? [String: Any])
        let messages = try #require(bodyJSON["messages"] as? [[String: String]])
        #expect(messages.last?["content"]?.contains("Although tired, she continued.") == true)
        #expect(messages.last?["content"]?.contains("went home") == false)
        #expect(messages.last?["content"]?.contains("1 to 3 useful grammarPoints") == true)
    }

    @Test func safelyDropsOffTargetItemsFromRepairResponse() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let offTarget = Explanation(
            translation: "她继续了。", sentenceCore: "她继续了。",
            grammarPoints: [.init(text: "她", explanation: "主语")],
            keyPhrases: [.init(text: "她继续了", meaning: "继续")]
        )
        let raw = String(decoding: try JSONEncoder().encode(offTarget), as: UTF8.self)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope(raw)), .success(chatEnvelope(raw))])
        let request = ExplanationRequest(targetText: "She continued.")

        let result = try await OllamaReadingAI(client: client).explain(request)

        #expect(result.translation == "她继续了。")
        #expect(result.sentenceCore == request.targetText)
        #expect(result.grammarPoints.isEmpty)
        #expect(result.keyPhrases.isEmpty)
    }

    @Test func repairKeepsValidItemsWhileDroppingHallucinatedOnes() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let first = Explanation(
            translation: "尽管疲惫，她仍继续。", sentenceCore: "她仍继续",
            grammarPoints: [], keyPhrases: []
        )
        let repaired = Explanation(
            translation: "尽管疲惫，她仍继续。", sentenceCore: "她仍继续",
            grammarPoints: [
                .init(text: "Although tired", explanation: "让步结构"),
                .init(text: "went home", explanation: "虚构内容")
            ],
            keyPhrases: [
                .init(text: "she continued", meaning: "她继续了"),
                .init(text: "gave up", meaning: "虚构内容")
            ]
        )
        let encode: (Explanation) throws -> String = { value in
            String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        }
        let client = StubHTTPClient([
            .success(tags),
            .success(chatEnvelope(try encode(first))),
            .success(chatEnvelope(try encode(repaired)))
        ])
        let request = ExplanationRequest(targetText: "Although tired, she continued.")

        let result = try await OllamaReadingAI(model: "qwen2.5:1.5b-instruct", client: client).explain(request)

        #expect(result.sentenceCore == request.targetText)
        #expect(result.grammarPoints == [.init(text: "Although tired", explanation: "让步结构")])
        #expect(result.keyPhrases == [.init(text: "she continued", meaning: "她继续了")])
    }

    @Test func failsAfterOneRetry() async {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("bad")), .success(chatEnvelope("still bad"))])
        await #expect(throws: ReadingAIError.self) {
            try await OllamaReadingAI(client: client).explain(.init(targetText: "Hello"))
        }
        #expect(await client.requests.count == 3)
    }

    @Test func batchAttemptPreservesInvalidRawAfterRetry() async {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope("bad")), .success(chatEnvelope("still bad"))])
        let attempt = await OllamaReadingAI(client: client).attemptExplanation(.init(targetText: "Hello"))
        #expect(!attempt.jsonValid)
        #expect(attempt.explanation == nil)
        #expect(attempt.raw == "still bad")
        #expect(attempt.error?.contains("Invalid model response") == true)
    }

    @Test func deepAnalysisUsesLargerStrictSchema() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let raw = String(decoding: try JSONEncoder().encode(sampleDeepAnalysis), as: UTF8.self)
        let client = StubHTTPClient([.success(tags), .success(chatEnvelope(raw))])
        let request = ExplanationRequest(targetText: "Although tired, she continued.")

        #expect(try await OllamaReadingAI(client: client).analyzeDeep(request) == sampleDeepAnalysis)
        let body = try #require((await client.requests).last?.body)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let options = try #require(json["options"] as? [String: Any])
        #expect(options["num_predict"] as? Int == 700)
        let format = try #require(json["format"] as? [String: Any])
        let required = try #require(format["required"] as? [String])
        #expect(Set(required).contains("components"))
        #expect(Set(required).contains("clauses"))
    }

    @Test func partialParserExposesTranslationAndCompletedGrammarBeforeJSONFinishes() throws {
        let translation = try #require(PartialExplanationParser.parse(#"{"translation":"火车正"#))
        #expect(translation.translation == "火车正")
        #expect(translation.grammarPoints.isEmpty)

        let grammar = try #require(PartialExplanationParser.parse(
            #"{"translation":"火车正在出发。","sentenceCore":"The train leaves.","grammarPoints":[{"text":"leaves","explanation":"一般现在时"}],"keyPhrases":["#
        ))
        #expect(grammar.sentenceCore == "The train leaves.")
        #expect(grammar.grammarPoints == [.init(text: "leaves", explanation: "一般现在时")])
    }

    @Test func streamsPreviewUpdatesThenValidatedFinalExplanation() async throws {
        let tags = response(200, #"{"models":[{"name":"qwen2.5:1.5b-instruct"}]}"#)
        let chunks = [
            #"{"translation":"尽管很"#,
            #"累，她仍继续。","sentenceCore":"Although tired, she continued.","grammarPoints":[{"text":"Although tired","explanation":"让步结构"}],"keyPhrases":[{"text":"she continued","meaning":"她继续"}]}"#
        ].map(streamEnvelope)
        let client = StubStreamingHTTPClient(tags: tags, streamLines: chunks)
        let provider = OllamaReadingAI(client: client)
        let stream = try await provider.explanationStream(.init(targetText: "Although tired, she continued."))
        var updates: [Explanation] = []
        for try await update in stream { updates.append(update) }

        #expect(updates.first?.translation == "尽管很")
        #expect(updates.last?.grammarPoints == [.init(text: "Although tired", explanation: "让步结构")])
        #expect(updates.last?.keyPhrases == [.init(text: "she continued", meaning: "她继续")])
        let requests = await client.requests
        let body = try #require(requests.last?.body)
        let bodyJSON = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(bodyJSON["stream"] as? Bool == true)
    }
}

private func response(_ status: Int, _ string: String) -> HTTPResponse { .init(statusCode: status, data: Data(string.utf8)) }
private func chatEnvelope(_ content: String) -> HTTPResponse {
    let data = try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
    return .init(statusCode: 200, data: data)
}
private func streamEnvelope(_ content: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content], "done": false])
}
private var validJSON: String { String(decoding: try! JSONEncoder().encode(sampleExplanation), as: UTF8.self) }
