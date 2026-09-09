import Foundation

public struct WordExplanationRequest: Codable, Equatable, Sendable {
    public let selectedText: String
    public let sentenceContext: String
    public let precedingContext: String?
    public let followingContext: String?
    public let sourceLanguage: String
    public let explanationLanguage: String

    public init(
        selectedText: String,
        sentenceContext: String,
        precedingContext: String? = nil,
        followingContext: String? = nil,
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) {
        self.selectedText = selectedText
        self.sentenceContext = sentenceContext
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.sourceLanguage = sourceLanguage
        self.explanationLanguage = explanationLanguage
    }

    public func validated() throws -> Self {
        guard !selectedText.trimmed.isEmpty else {
            throw ReadingAIError.invalidInput("selectedText must not be empty")
        }
        guard selectedText.count <= 120 else {
            throw ReadingAIError.invalidInput("selectedText exceeds 120 characters")
        }
        guard !sentenceContext.trimmed.isEmpty, sentenceContext.count <= 2_000 else {
            throw ReadingAIError.invalidInput("sentenceContext must contain 1 to 2000 characters")
        }
        for (name, value) in [("precedingContext", precedingContext), ("followingContext", followingContext)] {
            if let value, value.count > 2_000 {
                throw ReadingAIError.invalidInput("\(name) exceeds 2000 characters")
            }
        }
        guard !sourceLanguage.trimmed.isEmpty, !explanationLanguage.trimmed.isEmpty else {
            throw ReadingAIError.invalidInput("language names must not be empty")
        }
        return self
    }
}

public struct WordCollocation: Codable, Equatable, Sendable {
    public let text: String
    public let meaning: String

    public init(text: String, meaning: String) {
        self.text = text
        self.meaning = meaning
    }
}

public struct WordExplanation: Codable, Equatable, Sendable {
    public let surface: String
    public let lemma: String
    public let reading: String?
    public let partOfSpeech: String
    public let contextualMeaning: String
    public let briefMeaning: String
    public let inflection: String?
    public let collocations: [WordCollocation]

    public init(
        surface: String,
        lemma: String,
        reading: String? = nil,
        partOfSpeech: String,
        contextualMeaning: String,
        briefMeaning: String,
        inflection: String? = nil,
        collocations: [WordCollocation] = []
    ) {
        self.surface = surface
        self.lemma = lemma
        self.reading = reading?.trimmed.nilIfEmpty
        self.partOfSpeech = partOfSpeech
        self.contextualMeaning = contextualMeaning
        self.briefMeaning = briefMeaning
        self.inflection = inflection?.trimmed.nilIfEmpty
        self.collocations = collocations
    }

    public func validated(against request: WordExplanationRequest) throws -> Self {
        guard surface.sourceKey == request.selectedText.sourceKey else {
            throw ReadingAIError.invalidResponse("surface does not match selectedText")
        }
        guard !lemma.trimmed.isEmpty, !partOfSpeech.trimmed.isEmpty,
              !contextualMeaning.trimmed.isEmpty, !briefMeaning.trimmed.isEmpty else {
            throw ReadingAIError.invalidResponse("word explanation contains empty required fields")
        }
        guard collocations.count <= 4,
              collocations.allSatisfy({ !$0.text.trimmed.isEmpty && !$0.meaning.trimmed.isEmpty }) else {
            throw ReadingAIError.invalidResponse("invalid collocations")
        }
        return self
    }
}

public protocol VocabularyAI: Sendable {
    func explainWord(_ request: WordExplanationRequest) async throws -> WordExplanation
}

public protocol StreamingVocabularyAI: VocabularyAI {
    /// Intermediate values are display-only. The final value is fully validated.
    func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<WordExplanation, Error>
}

public struct MockVocabularyAI: StreamingVocabularyAI {
    public init() {}

    public func explainWord(_ request: WordExplanationRequest) async throws -> WordExplanation {
        try result(for: request).validated(against: request.validated())
    }

    public func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<WordExplanation, Error> {
        let result = try await explainWord(request)
        return AsyncThrowingStream { continuation in
            continuation.yield(result)
            continuation.finish()
        }
    }

    private func result(for request: WordExplanationRequest) -> WordExplanation {
        WordExplanation(
            surface: request.selectedText,
            lemma: request.selectedText,
            partOfSpeech: "Mock",
            contextualMeaning: "“\(request.selectedText)”在当前语境中的示例含义。",
            briefMeaning: "示例释义",
            collocations: []
        )
    }
}

public enum VocabularyPrompt {
    public static let system = """
    You are a concise dictionary assistant. Explain selectedText only. Context may determine its meaning but is not the target.
    Copy surface exactly from selectedText. Never replace it with a word found only in context.
    Write contextualMeaning, briefMeaning, inflection, and collocations.meaning in explanationLanguage.
    Keep lemma, reading, partOfSpeech, and collocations.text in sourceLanguage. Use an empty string for unknown reading or inflection.
    Return JSON only, with keys in this order: surface, lemma, reading, partOfSpeech, contextualMeaning, briefMeaning, inflection, collocations.
    """

    public static func user(_ request: WordExplanationRequest) -> String {
        let payload = Input(
            task: "Explain selectedText in its sentence context",
            outputLanguageRule: QwenPrompt.explanationLanguageRule(for: request.explanationLanguage),
            selectedText: request.selectedText,
            sentenceContext: request.sentenceContext,
            precedingContext: request.precedingContext,
            followingContext: request.followingContext,
            sourceLanguage: request.sourceLanguage,
            explanationLanguage: request.explanationLanguage
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(payload)) ?? Data("{}".utf8), as: UTF8.self)
    }

    public static func repair(_ request: WordExplanationRequest) -> String {
        """
        The previous answer failed validation. Explain only selectedText: \(request.selectedText)
        Copy surface exactly as: \(request.selectedText)
        Context is reference only and must never replace surface. Write meanings in \(request.explanationLanguage).
        Return all required JSON fields. Use empty strings for unknown reading and inflection, and at most 4 collocations.
        """
    }

    private struct Input: Codable {
        let task: String
        let outputLanguageRule: String
        let selectedText: String
        let sentenceContext: String
        let precedingContext: String?
        let followingContext: String?
        let sourceLanguage: String
        let explanationLanguage: String
    }
}

public enum WordExplanationParser {
    public static func parse(_ raw: String, request: WordExplanationRequest) throws -> WordExplanation {
        let cleaned = ExplanationParser.stripMarkdownFence(raw).trimmed
        guard let data = cleaned.data(using: .utf8) else {
            throw ReadingAIError.invalidResponse("word response is not UTF-8")
        }
        do {
            let decoded = try JSONDecoder().decode(WordExplanation.self, from: data)
            return try LocalVocabularyEnricher.enrich(decoded, request: request).validated(against: request)
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.invalidResponse(error.localizedDescription)
        }
    }
}

public enum LocalVocabularyEnricher {
    private static let cachedJapaneseMorphology = try? MeCabJapaneseReadingProvider()

    public static func enrich(
        _ explanation: WordExplanation,
        request: WordExplanationRequest,
        morphology: (any JapaneseMorphologyProviding)? = nil
    ) -> WordExplanation {
        guard request.sourceLanguage.localizedCaseInsensitiveContains("Japanese") else {
            return explanation
        }
        let provider = morphology ?? cachedJapaneseMorphology
        guard let provider else { return explanation }
        let tokens = provider.tokens(for: request.selectedText).filter { $0.partOfSpeech != "symbol" }
        guard !tokens.isEmpty else { return explanation }
        let lemma = tokens.map(\.dictionaryForm).joined()
        let reading = tokens.map(\.reading).joined()
        let parts = tokens.map(\.partOfSpeech).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        let inflected = tokens.filter(\.isInflected)
        let inflection: String? = inflected.isEmpty
            ? nil
            : inflected.map { "\($0.surface) → \($0.dictionaryForm)" }.joined(separator: "、")
        return WordExplanation(
            surface: request.selectedText,
            lemma: lemma.isEmpty ? request.selectedText : lemma,
            reading: reading,
            partOfSpeech: parts.joined(separator: " / "),
            contextualMeaning: explanation.contextualMeaning,
            briefMeaning: explanation.briefMeaning,
            inflection: inflection,
            collocations: explanation.collocations
        )
    }
}

public struct OllamaVocabularyAI<Client: HTTPClient>: VocabularyAI {
    public let baseURL: URL
    public let model: String
    public let client: Client
    public let timeout: TimeInterval

    public init(baseURL: URL, model: String, client: Client, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.model = model
        self.client = client
        self.timeout = timeout
    }

    public func explainWord(_ request: WordExplanationRequest) async throws -> WordExplanation {
        let valid = try request.validated()
        let raw = try await completion(valid, repair: false)
        do { return try WordExplanationParser.parse(raw, request: valid) }
        catch { return try WordExplanationParser.parse(try await completion(valid, repair: true), request: valid) }
    }

    public func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<WordExplanation, Error> where Client: StreamingHTTPClient {
        let valid = try request.validated()
        let body = try JSONEncoder().encode(OllamaWordRequest(
            model: model,
            messages: messages(valid, repair: false),
            stream: true,
            format: .word(request: valid),
            options: .init(temperature: 0, numPredict: 300)
        ))
        let stream = try await client.stream(try httpRequest(body: body))
        guard (200..<300).contains(stream.statusCode) else {
            throw ReadingAIError.serviceUnavailable("HTTP \(stream.statusCode)")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var raw = ""
                var last: WordExplanation?
                do {
                    for try await line in stream.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty else { continue }
                        let event = try JSONDecoder().decode(OllamaWordStreamEvent.self, from: line)
                        if let error = event.error { throw ReadingAIError.serviceUnavailable(error) }
                        raw += event.message?.content ?? ""
                        if let preview = PartialWordExplanationParser.parse(raw, request: valid), preview != last {
                            last = preview
                            continuation.yield(preview)
                        }
                    }
                    try Task.checkCancellation()
                    let final: WordExplanation
                    do { final = try WordExplanationParser.parse(raw, request: valid) }
                    catch { final = try WordExplanationParser.parse(try await completion(valid, repair: true), request: valid) }
                    if final != last { continuation.yield(final) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func completion(_ request: WordExplanationRequest, repair: Bool) async throws -> String {
        let body = try JSONEncoder().encode(OllamaWordRequest(
            model: model,
            messages: messages(request, repair: repair),
            stream: false,
            format: .word(request: request),
            options: .init(temperature: 0, numPredict: 300)
        ))
        let response = try await client.send(try httpRequest(body: body))
        guard (200..<300).contains(response.statusCode) else {
            throw ReadingAIError.serviceUnavailable("HTTP \(response.statusCode)")
        }
        do { return try JSONDecoder().decode(OllamaWordResponse.self, from: response.data).message.content }
        catch { throw ReadingAIError.invalidResponse("invalid Ollama envelope: \(error.localizedDescription)") }
    }

    private func messages(_ request: WordExplanationRequest, repair: Bool) -> [VocabularyMessage] {
        [.init(role: "system", content: VocabularyPrompt.system),
         .init(role: "user", content: repair ? VocabularyPrompt.repair(request) : VocabularyPrompt.user(request))]
    }

    private func httpRequest(body: Data) throws -> HTTPRequest {
        guard let url = URL(string: "/api/chat", relativeTo: baseURL)?.absoluteURL else {
            throw ReadingAIError.invalidInput("invalid Ollama URL")
        }
        return .init(url: url, method: "POST", headers: ["Content-Type": "application/json"], body: body, timeout: timeout)
    }
}

public extension OllamaVocabularyAI where Client == URLSessionHTTPClient {
    init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        model: String = OllamaDefaults.model,
        timeout: TimeInterval = 60
    ) {
        self.init(baseURL: baseURL, model: model, client: URLSessionHTTPClient(), timeout: timeout)
    }
}

extension OllamaVocabularyAI: StreamingVocabularyAI where Client: StreamingHTTPClient {}

public struct OpenAICompatibleVocabularyAI<Client: HTTPClient>: VocabularyAI {
    public let baseURL: URL
    public let apiKey: String
    public let model: String
    public let client: Client
    public let timeout: TimeInterval

    public init(baseURL: URL, apiKey: String, model: String, client: Client, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.client = client
        self.timeout = timeout
    }

    public func explainWord(_ request: WordExplanationRequest) async throws -> WordExplanation {
        let valid = try request.validated()
        let raw = try await completion(valid, repair: false)
        do { return try WordExplanationParser.parse(raw, request: valid) }
        catch { return try WordExplanationParser.parse(try await completion(valid, repair: true), request: valid) }
    }

    public func wordExplanationStream(
        _ request: WordExplanationRequest
    ) async throws -> AsyncThrowingStream<WordExplanation, Error> where Client: StreamingHTTPClient {
        let valid = try request.validated()
        let body = try requestBody(valid, repair: false, stream: true)
        let response = try await client.stream(try authorizedRequest(body: body))
        guard (200..<300).contains(response.statusCode) else {
            throw ReadingAIError.serviceUnavailable("云端服务返回 HTTP \(response.statusCode)")
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                var raw = ""
                var last: WordExplanation?
                do {
                    for try await lineData in response.lines {
                        try Task.checkCancellation()
                        guard var line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                        if line.hasPrefix("data:") { line.removeFirst(5); line = line.trimmed }
                        if line == "[DONE]" { break }
                        guard let data = line.data(using: .utf8) else { continue }
                        let event = try JSONDecoder().decode(OpenAIWordStreamEvent.self, from: data)
                        if let message = event.error?.message { throw ReadingAIError.serviceUnavailable(message) }
                        raw += event.choices.first?.delta.content ?? ""
                        if let preview = PartialWordExplanationParser.parse(raw, request: valid), preview != last {
                            last = preview
                            continuation.yield(preview)
                        }
                    }
                    try Task.checkCancellation()
                    let final: WordExplanation
                    do { final = try WordExplanationParser.parse(raw, request: valid) }
                    catch { final = try WordExplanationParser.parse(try await completion(valid, repair: true), request: valid) }
                    if final != last { continuation.yield(final) }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func completion(_ request: WordExplanationRequest, repair: Bool) async throws -> String {
        let response = try await client.send(try authorizedRequest(body: try requestBody(request, repair: repair, stream: false)))
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(OpenAIWordErrorEnvelope.self, from: response.data).error.message)
            throw ReadingAIError.serviceUnavailable(message ?? "云端服务返回 HTTP \(response.statusCode)")
        }
        do {
            guard let content = try JSONDecoder().decode(OpenAIWordResponse.self, from: response.data)
                .choices.first?.message.content, !content.isEmpty else {
                throw ReadingAIError.invalidResponse("云端响应没有文本内容")
            }
            return content
        } catch let error as ReadingAIError { throw error }
        catch { throw ReadingAIError.invalidResponse("无法解析云端响应：\(error.localizedDescription)") }
    }

    private func requestBody(_ request: WordExplanationRequest, repair: Bool, stream: Bool) throws -> Data {
        try JSONEncoder().encode(OpenAIWordRequest(
            model: model,
            messages: [.init(role: "system", content: VocabularyPrompt.system),
                       .init(role: "user", content: repair ? VocabularyPrompt.repair(request) : VocabularyPrompt.user(request))],
            stream: stream,
            temperature: 0,
            maxTokens: 300,
            responseFormat: .init(type: "json_object")
        ))
    }

    private func authorizedRequest(body: Data) throws -> HTTPRequest {
        guard let scheme = baseURL.scheme?.lowercased(), ["http", "https"].contains(scheme), baseURL.host != nil else {
            throw ReadingAIError.invalidInput("云端 API 地址无效")
        }
        let key = apiKey.trimmed
        guard !key.isEmpty else { throw ReadingAIError.invalidInput("API Key 不能为空") }
        guard !model.trimmed.isEmpty else { throw ReadingAIError.invalidInput("云端模型名称不能为空") }
        return .init(
            url: baseURL.appendingPathComponent("chat/completions"),
            method: "POST",
            headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
            body: body,
            timeout: timeout
        )
    }
}

public extension OpenAICompatibleVocabularyAI where Client == URLSessionHTTPClient {
    init(baseURL: URL, apiKey: String, model: String, timeout: TimeInterval = 60) {
        self.init(baseURL: baseURL, apiKey: apiKey, model: model, client: URLSessionHTTPClient(), timeout: timeout)
    }
}

extension OpenAICompatibleVocabularyAI: StreamingVocabularyAI where Client: StreamingHTTPClient {}

private struct VocabularyMessage: Codable, Sendable { let role: String; let content: String }
private struct OllamaWordOptions: Codable, Sendable {
    let temperature: Double
    let numPredict: Int
    enum CodingKeys: String, CodingKey { case temperature; case numPredict = "num_predict" }
}
private struct OllamaWordRequest: Encodable, Sendable {
    let model: String
    let messages: [VocabularyMessage]
    let stream: Bool
    let format: VocabularySchema
    let options: OllamaWordOptions
}
private struct OllamaWordResponse: Decodable { let message: VocabularyMessage }
private struct OllamaWordStreamEvent: Decodable { let message: VocabularyMessage?; let error: String? }
private struct OpenAIWordResponse: Decodable {
    struct Choice: Decodable { let message: VocabularyMessage }
    let choices: [Choice]
}
private struct OpenAIWordStreamEvent: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
    let error: OpenAIWordAPIError?
}
private struct OpenAIWordAPIError: Decodable { let message: String }
private struct OpenAIWordErrorEnvelope: Decodable { let error: OpenAIWordAPIError }
private struct OpenAIWordResponseFormat: Codable, Sendable { let type: String }
private struct OpenAIWordRequest: Encodable, Sendable {
    let model: String
    let messages: [VocabularyMessage]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let responseFormat: OpenAIWordResponseFormat
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private indirect enum VocabularySchema: Encodable, Sendable {
    case string(String), integer(Int), array([VocabularySchema]), object([String: VocabularySchema])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func word(request: WordExplanationRequest) -> Self {
        let explained = "Write in \(request.explanationLanguage). \(QwenPrompt.explanationLanguageRule(for: request.explanationLanguage))"
        func text(_ description: String) -> Self { .object(["type": .string("string"), "description": .string(description)]) }
        return .object([
            "type": .string("object"),
            "properties": .object([
                "surface": text("Copy selectedText exactly: \(request.selectedText)"),
                "lemma": text("Dictionary form in \(request.sourceLanguage)"),
                "reading": text("Pronunciation or kana reading; empty string when unknown"),
                "partOfSpeech": text("Part of speech in \(request.sourceLanguage)"),
                "contextualMeaning": text("Meaning specifically in sentenceContext. \(explained)"),
                "briefMeaning": text("Short dictionary meaning. \(explained)"),
                "inflection": text("Inflection from lemma to surface. \(explained); empty string if none"),
                "collocations": .object([
                    "type": .string("array"), "maxItems": .integer(4),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object(["text": text("Common collocation in source language"), "meaning": text(explained)]),
                        "required": .array([.string("text"), .string("meaning")])
                    ])
                ])
            ]),
            "required": .array(["surface", "lemma", "reading", "partOfSpeech", "contextualMeaning", "briefMeaning", "inflection", "collocations"].map(Self.string))
        ])
    }
}

enum PartialWordExplanationParser {
    static func parse(_ raw: String, request: WordExplanationRequest) -> WordExplanation? {
        guard let contextual = value("contextualMeaning", raw), !contextual.isEmpty else { return nil }
        let result = WordExplanation(
            surface: request.selectedText,
            lemma: value("lemma", raw) ?? request.selectedText,
            reading: value("reading", raw),
            partOfSpeech: value("partOfSpeech", raw) ?? "",
            contextualMeaning: contextual,
            briefMeaning: value("briefMeaning", raw) ?? contextual,
            inflection: value("inflection", raw),
            collocations: []
        )
        return LocalVocabularyEnricher.enrich(result, request: request)
    }

    private static func value(_ key: String, _ raw: String) -> String? {
        guard let keyRange = raw.range(of: "\"\(key)\"") else { return nil }
        let tail = raw[keyRange.upperBound...]
        guard let colon = tail.firstIndex(of: ":") else { return nil }
        let afterColon = tail[tail.index(after: colon)...].drop(while: \.isWhitespace)
        guard afterColon.first == "\"" else { return nil }
        var escaped = false
        var value = ""
        for character in afterColon.dropFirst() {
            if escaped {
                switch character { case "n": value.append("\n"); case "t": value.append("\t"); default: value.append(character) }
                escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "\"" { return value }
            else { value.append(character) }
        }
        return value.isEmpty ? nil : value
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
    var sourceKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}
