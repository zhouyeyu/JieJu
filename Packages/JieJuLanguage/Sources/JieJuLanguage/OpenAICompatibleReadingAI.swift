import Foundation

/// A small OpenAI Chat Completions compatible client. It deliberately keeps the
/// language-learning prompt and validation in JieJuLanguage so local and cloud
/// providers produce the same domain model.
public struct OpenAICompatibleReadingAI<Client: HTTPClient>: ReadingAI, DeepReadingAI {
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

    public func checkAvailability() async throws {
        _ = try validatedConfiguration()
        let response = try await send(path: "models", method: "GET")
        try validateStatus(response)
    }

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        let valid = try request.validated()
        let raw = try await completion(messages: explanationMessages(for: valid), maxTokens: 350)
        do {
            return try ExplanationParser.parse(raw).validated(against: valid)
        } catch {
            let repaired = try await completion(messages: [
                .init(role: "system", content: QwenPrompt.system),
                .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: raw))
            ], maxTokens: 350)
            return try ExplanationParser.parse(repaired).validated(against: valid)
        }
    }

    public func analyzeDeep(_ request: ExplanationRequest) async throws -> DeepAnalysis {
        let valid = try request.validated()
        if valid.sourceLanguage.localizedCaseInsensitiveContains("Japanese") {
            return try JapaneseGrammarAnalyzer.localAnalysis(request: valid)
        }
        let raw = try await completion(messages: [
            .init(role: "system", content: DeepQwenPrompt.system(for: valid)),
            .init(role: "user", content: DeepQwenPrompt.user(valid))
        ], maxTokens: 700)
        do {
            return try DeepAnalysisParser.parse(raw, request: valid)
        } catch {
            let repaired = try await completion(messages: [
                .init(role: "system", content: DeepQwenPrompt.system(for: valid)),
                .init(role: "user", content: DeepQwenPrompt.repair(valid))
            ], maxTokens: 700)
            return try DeepAnalysisParser.parse(repaired, request: valid)
        }
    }

    public func explanationStream(
        _ request: ExplanationRequest
    ) async throws -> AsyncThrowingStream<Explanation, Error> where Client: StreamingHTTPClient {
        let valid = try request.validated()
        _ = try validatedConfiguration()
        let body = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: explanationMessages(for: valid),
            stream: true,
            temperature: 0,
            maxTokens: 350,
            responseFormat: .init(type: "json_object")
        ))
        let response = try await client.stream(try authorizedRequest(path: "chat/completions", method: "POST", body: body))
        guard (200..<300).contains(response.statusCode) else {
            throw ReadingAIError.serviceUnavailable("云端服务返回 HTTP \(response.statusCode)")
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var raw = ""
                var lastPreview: Explanation?
                do {
                    for try await lineData in response.lines {
                        try Task.checkCancellation()
                        guard var line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
                        if line.hasPrefix("data:") {
                            line.removeFirst(5)
                            line = line.trimmingCharacters(in: .whitespaces)
                        }
                        if line == "[DONE]" { break }
                        guard let data = line.data(using: .utf8) else { continue }
                        let event = try JSONDecoder().decode(StreamEnvelope.self, from: data)
                        if let message = event.error?.message { throw ReadingAIError.serviceUnavailable(message) }
                        raw += event.choices.first?.delta.content ?? ""
                        if let preview = PartialExplanationParser.parse(raw), preview != lastPreview {
                            lastPreview = preview
                            continuation.yield(preview)
                        }
                    }
                    let final: Explanation
                    do {
                        final = try ExplanationParser.parse(raw).validated(against: valid)
                    } catch {
                        let repaired = try await completion(messages: [
                            .init(role: "system", content: QwenPrompt.system),
                            .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: raw))
                        ], maxTokens: 350)
                        final = try ExplanationParser.parse(repaired).validated(against: valid)
                    }
                    if final != lastPreview { continuation.yield(final) }
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

    private func explanationMessages(for request: ExplanationRequest) -> [Message] {
        [
            .init(role: "system", content: QwenPrompt.system),
            .init(role: "user", content: QwenPrompt.user(request))
        ]
    }

    private func completion(messages: [Message], maxTokens: Int) async throws -> String {
        _ = try validatedConfiguration()
        let body = try JSONEncoder().encode(ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            temperature: 0,
            maxTokens: maxTokens,
            responseFormat: .init(type: "json_object")
        ))
        let response = try await send(path: "chat/completions", method: "POST", body: body)
        try validateStatus(response)
        do {
            let envelope = try JSONDecoder().decode(CompletionEnvelope.self, from: response.data)
            guard let content = envelope.choices.first?.message.content, !content.isEmpty else {
                throw ReadingAIError.invalidResponse("云端响应没有文本内容")
            }
            return content
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.invalidResponse("无法解析云端响应：\(error.localizedDescription)")
        }
    }

    private func send(path: String, method: String, body: Data? = nil) async throws -> HTTPResponse {
        try await client.send(try authorizedRequest(path: path, method: method, body: body))
    }

    private func authorizedRequest(path: String, method: String, body: Data?) throws -> HTTPRequest {
        let configuration = try validatedConfiguration()
        let url = configuration.baseURL.appendingPathComponent(path)
        var headers = ["Authorization": "Bearer \(configuration.apiKey)"]
        if body != nil { headers["Content-Type"] = "application/json" }
        return HTTPRequest(url: url, method: method, headers: headers, body: body, timeout: timeout)
    }

    private func validatedConfiguration() throws -> (baseURL: URL, apiKey: String) {
        guard let scheme = baseURL.scheme?.lowercased(), ["http", "https"].contains(scheme), baseURL.host != nil else {
            throw ReadingAIError.invalidInput("云端 API 地址无效")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ReadingAIError.invalidInput("API Key 不能为空") }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("云端模型名称不能为空")
        }
        return (baseURL, key)
    }

    private func validateStatus(_ response: HTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: response.data).error.message)
            throw ReadingAIError.serviceUnavailable(message ?? "云端服务返回 HTTP \(response.statusCode)")
        }
    }
}

public extension OpenAICompatibleReadingAI where Client == URLSessionHTTPClient {
    init(baseURL: URL, apiKey: String, model: String, timeout: TimeInterval = 60) {
        self.init(baseURL: baseURL, apiKey: apiKey, model: model, client: URLSessionHTTPClient(), timeout: timeout)
    }
}

extension OpenAICompatibleReadingAI: StreamingReadingAI where Client: StreamingHTTPClient {}

private struct Message: Codable, Sendable {
    let role: String
    let content: String
}

private struct ResponseFormat: Codable, Sendable { let type: String }

private struct ChatRequest: Encodable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
        case responseFormat = "response_format"
    }
}

private struct CompletionEnvelope: Decodable {
    struct Choice: Decodable { let message: Message }
    let choices: [Choice]
}

private struct StreamEnvelope: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
    let error: APIError?
}

private struct APIError: Decodable { let message: String }
private struct ErrorEnvelope: Decodable { let error: APIError }
