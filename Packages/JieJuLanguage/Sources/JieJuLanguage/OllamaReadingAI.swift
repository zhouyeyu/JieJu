import Foundation

public struct OllamaModel: Codable, Equatable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public enum OllamaDiagnostic: Equatable, Sendable {
    case ready(model: String, installedModelCount: Int)
    case modelMissing(required: String, installedModels: [String])
    case serviceUnavailable(message: String)
}

public struct OllamaReadingAI<Client: HTTPClient>: ReadingAI, BatchReadingAI {
    public static var defaultModel: String { "qwen2.5:0.5b-instruct" }
    public let baseURL: URL
    public let model: String
    public let client: Client
    public let timeout: TimeInterval

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = Self.defaultModel, client: Client, timeout: TimeInterval = 60) {
        self.baseURL = baseURL
        self.model = model
        self.client = client
        self.timeout = timeout
    }

    public func isHealthy() async throws -> Bool {
        let response = try await send(path: "/api/tags")
        return (200..<300).contains(response.statusCode)
    }

    public func models() async throws -> [OllamaModel] {
        let response = try await send(path: "/api/tags")
        guard (200..<300).contains(response.statusCode) else {
            throw ReadingAIError.serviceUnavailable("HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(ModelList.self, from: response.data).models
        } catch {
            throw ReadingAIError.invalidResponse("invalid model list: \(error.localizedDescription)")
        }
    }

    public func hasModel(_ requestedModel: String? = nil) async throws -> Bool {
        let wanted = requestedModel ?? model
        return try await models().contains { $0.name == wanted || $0.name == "\(wanted):latest" }
    }

    public func diagnose() async -> OllamaDiagnostic {
        do {
            let installed = try await models().map(\.name).sorted()
            let found = installed.contains { $0 == model || $0 == "\(model):latest" }
            return found
                ? .ready(model: model, installedModelCount: installed.count)
                : .modelMissing(required: model, installedModels: installed)
        } catch {
            return .serviceUnavailable(message: error.localizedDescription)
        }
    }

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        let result = try await explainWithRawResponse(request)
        return result.explanation
    }

    public func explainWithRawResponse(_ request: ExplanationRequest) async throws -> (explanation: Explanation, rawResponse: String) {
        let valid = try request.validated()
        guard try await hasModel() else { throw ReadingAIError.modelMissing(model) }
        let first = try await generate(messages: [
            .init(role: "system", content: QwenPrompt.system),
            .init(role: "user", content: QwenPrompt.user(valid))
        ])
        do {
            return (try ExplanationParser.parse(first).validated(against: valid), first)
        } catch {
            let repaired = try await generate(messages: [
                .init(role: "system", content: QwenPrompt.system),
                .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: first))
            ])
            return (try ExplanationParser.parse(repaired).validated(against: valid), repaired)
        }
    }

    public func attemptExplanation(_ request: ExplanationRequest) async -> BatchAttempt {
        var latestRaw: String?
        do {
            let valid = try request.validated()
            guard try await hasModel() else { throw ReadingAIError.modelMissing(model) }
            let first = try await generate(messages: [
                .init(role: "system", content: QwenPrompt.system),
                .init(role: "user", content: QwenPrompt.user(valid))
            ])
            latestRaw = first
            do {
                return .init(explanation: try ExplanationParser.parse(first).validated(against: valid), raw: first, jsonValid: true)
            } catch {
                let repaired = try await generate(messages: [
                    .init(role: "system", content: QwenPrompt.system),
                    .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: first))
                ])
                latestRaw = repaired
                return .init(explanation: try ExplanationParser.parse(repaired).validated(against: valid), raw: repaired, jsonValid: true)
            }
        } catch {
            return .init(error: error.localizedDescription, raw: latestRaw, jsonValid: false)
        }
    }

    private func generate(messages: [ChatMessage]) async throws -> String {
        let body = ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            format: "json",
            options: .init(temperature: 0, numPredict: 700)
        )
        let data = try JSONEncoder().encode(body)
        let response = try await send(path: "/api/chat", method: "POST", body: data)
        guard (200..<300).contains(response.statusCode) else {
            throw ReadingAIError.serviceUnavailable("HTTP \(response.statusCode)")
        }
        do {
            return try JSONDecoder().decode(ChatResponse.self, from: response.data).message.content
        } catch {
            throw ReadingAIError.invalidResponse("invalid Ollama envelope: \(error.localizedDescription)")
        }
    }

    private func send(path: String, method: String = "GET", body: Data? = nil) async throws -> HTTPResponse {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ReadingAIError.invalidInput("invalid Ollama URL")
        }
        do {
            return try await client.send(.init(url: url, method: method, headers: body == nil ? [:] : ["Content-Type": "application/json"], body: body, timeout: timeout))
        } catch let error as ReadingAIError { throw error }
        catch { throw ReadingAIError.transport(error.localizedDescription) }
    }
}

private struct ModelList: Codable { let models: [OllamaModel] }
private struct ChatMessage: Codable { let role: String; let content: String }
private struct ChatOptions: Codable {
    let temperature: Double
    let numPredict: Int
    enum CodingKeys: String, CodingKey { case temperature; case numPredict = "num_predict" }
}
private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let format: String
    let options: ChatOptions
}
private struct ChatResponse: Codable { let message: ChatMessage }

public extension OllamaReadingAI where Client == URLSessionHTTPClient {
    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = Self.defaultModel, timeout: TimeInterval = 60) {
        self.init(baseURL: baseURL, model: model, client: URLSessionHTTPClient(), timeout: timeout)
    }
}
