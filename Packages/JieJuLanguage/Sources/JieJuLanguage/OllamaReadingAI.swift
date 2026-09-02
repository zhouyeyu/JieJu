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

public enum OllamaDefaults {
    public static let model = "qwen2.5:1.5b-instruct"
}

public struct OllamaReadingAI<Client: HTTPClient>: ReadingAI, DeepReadingAI, BatchReadingAI {
    public static var defaultModel: String { OllamaDefaults.model }
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
        ], request: valid, minimumItems: 1)
        do {
            return (try ExplanationParser.parse(first).validated(against: valid), first)
        } catch {
            let repaired = try await generate(messages: [
                .init(role: "system", content: QwenPrompt.system),
                .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: first))
            ], request: valid, minimumItems: 1)
            let parsed = try ExplanationParser.parse(repaired)
            return (try validatedRepair(parsed, request: valid), repaired)
        }
    }

    public func analyzeDeep(_ request: ExplanationRequest) async throws -> DeepAnalysis {
        try await analyzeDeepWithRawResponse(request).analysis
    }

    public func analyzeDeepWithRawResponse(_ request: ExplanationRequest) async throws -> (analysis: DeepAnalysis, rawResponse: String) {
        let valid = try request.validated()
        if valid.sourceLanguage.localizedCaseInsensitiveContains("Japanese") {
            let analysis = try JapaneseGrammarAnalyzer.localAnalysis(request: valid)
            let raw = String(decoding: try JSONEncoder().encode(analysis), as: UTF8.self)
            return (analysis, raw)
        }
        guard try await hasModel() else { throw ReadingAIError.modelMissing(model) }
        let first = try await generateDeep(messages: [
            .init(role: "system", content: DeepQwenPrompt.system(for: valid)),
            .init(role: "user", content: DeepQwenPrompt.user(valid))
        ], request: valid)
        do {
            let parsed = try DeepAnalysisParser.parse(first, request: valid)
            return (try finalizedDeepAnalysis(parsed, request: valid), first)
        } catch {
            if let decoded = try? DeepAnalysisParser.decode(first),
               let repaired = try? validatedDeepRepair(decoded, request: valid) {
                return (try finalizedDeepAnalysis(repaired, request: valid), first)
            }
            let repaired = try await generateDeep(messages: [
                .init(role: "system", content: DeepQwenPrompt.system(for: valid)),
                .init(role: "user", content: DeepQwenPrompt.repair(valid))
            ], request: valid)
            let parsed = try DeepAnalysisParser.parse(repaired, request: valid)
            return (try finalizedDeepAnalysis(parsed, request: valid), repaired)
        }
    }

    private func finalizedDeepAnalysis(_ analysis: DeepAnalysis, request: ExplanationRequest) throws -> DeepAnalysis {
        try JapaneseGrammarAnalyzer.enrich(analysis, request: request).validated(against: request)
    }

    private func validatedDeepRepair(_ analysis: DeepAnalysis, request: ExplanationRequest) throws -> DeepAnalysis {
        let itemValidationRequest = ExplanationRequest(
            targetText: request.targetText,
            precedingContext: request.precedingContext,
            followingContext: request.followingContext,
            sourceLanguage: "FragmentValidation",
            explanationLanguage: request.explanationLanguage
        )
        func candidate(components: [SentenceComponent] = [], clauses: [ClauseExplanation] = [], grammar: [GrammarPoint] = [], words: [JapaneseWordAnalysis]? = nil) -> DeepAnalysis {
            .init(sentenceType: analysis.sentenceType, sentencePattern: analysis.sentencePattern,
                  components: components, clauses: clauses, grammarPoints: grammar,
                  interpretation: analysis.interpretation, japaneseWords: words)
        }
        let components = analysis.components.filter { (try? candidate(components: [$0]).validated(against: itemValidationRequest)) != nil }
        let clauses = analysis.clauses.filter { (try? candidate(clauses: [$0]).validated(against: itemValidationRequest)) != nil }
        let grammar = analysis.grammarPoints.filter {
            (try? candidate(grammar: [$0]).validated(against: itemValidationRequest)) != nil
        }
        let words = (analysis.japaneseWords ?? []).filter {
            (try? candidate(words: [$0]).validated(against: itemValidationRequest)) != nil
        }
        return try candidate(components: components, clauses: clauses, grammar: grammar, words: words).validated(against: request)
    }

    public func attemptExplanation(_ request: ExplanationRequest) async -> BatchAttempt {
        var latestRaw: String?
        do {
            let valid = try request.validated()
            guard try await hasModel() else { throw ReadingAIError.modelMissing(model) }
            let first = try await generate(messages: [
                .init(role: "system", content: QwenPrompt.system),
                .init(role: "user", content: QwenPrompt.user(valid))
            ], request: valid, minimumItems: 1)
            latestRaw = first
            do {
                return .init(explanation: try ExplanationParser.parse(first).validated(against: valid), raw: first, jsonValid: true)
            } catch {
                let repaired = try await generate(messages: [
                    .init(role: "system", content: QwenPrompt.system),
                    .init(role: "user", content: QwenPrompt.repair(request: valid, rawResponse: first))
                ], request: valid, minimumItems: 1)
                latestRaw = repaired
                let parsed = try ExplanationParser.parse(repaired)
                return .init(explanation: try validatedRepair(parsed, request: valid), raw: repaired, jsonValid: true)
            }
        } catch {
            return .init(error: error.localizedDescription, raw: latestRaw, jsonValid: false)
        }
    }

    private func validatedRepair(_ explanation: Explanation, request: ExplanationRequest) throws -> Explanation {
        do {
            return try explanation.validated(against: request)
        } catch {
            let grammarPoints = explanation.grammarPoints.filter { point in
                let candidate = Explanation(
                    translation: explanation.translation,
                    sentenceCore: request.targetText,
                    grammarPoints: [point],
                    keyPhrases: []
                )
                return (try? candidate.validated(against: request)) != nil
            }
            let keyPhrases = explanation.keyPhrases.filter { phrase in
                let candidate = Explanation(
                    translation: explanation.translation,
                    sentenceCore: request.targetText,
                    grammarPoints: [],
                    keyPhrases: [phrase]
                )
                return (try? candidate.validated(against: request)) != nil
            }
            return try Explanation(
                translation: explanation.translation,
                sentenceCore: request.targetText,
                grammarPoints: grammarPoints,
                keyPhrases: keyPhrases
            ).validated(against: request)
        }
    }

    private func generate(messages: [ChatMessage], request: ExplanationRequest, minimumItems: Int = 0) async throws -> String {
        let body = ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            format: .explanation(minimumItems: minimumItems, request: request),
            options: .init(temperature: 0, numPredict: 350)
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

    private func generateDeep(messages: [ChatMessage], request: ExplanationRequest) async throws -> String {
        let body = ChatRequest(
            model: model,
            messages: messages,
            stream: false,
            format: .deepAnalysis(request: request),
            options: .init(
                temperature: 0,
                numPredict: request.sourceLanguage.localizedCaseInsensitiveContains("Japanese") ? 560 : 700
            )
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
private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let format: SchemaValue
    let options: ChatOptions
}
private struct ChatResponse: Codable { let message: ChatMessage }

private indirect enum SchemaValue: Encodable {
    case string(String)
    case integer(Int)
    case array([SchemaValue])
    case object([String: SchemaValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    static func explanation(minimumItems: Int, request: ExplanationRequest) -> SchemaValue {
        let explanation = request.explanationLanguage
        let source = request.sourceLanguage
        let languageRule = QwenPrompt.explanationLanguageRule(for: explanation)
        return .object([
            "type": .string("object"),
            "properties": .object([
                "translation": .object([
                    "type": .string("string"),
                    "description": .string("Translate targetText into \(explanation). Write the translation in \(explanation), never in \(source). \(languageRule)")
                ]),
                "sentenceCore": .object([
                    "type": .string("string"),
                    "description": .string("Core sentence in \(source), copied exactly from targetText. Do not translate.")
                ]),
                "grammarPoints": .object([
                    "type": .string("array"), "minItems": .integer(minimumItems), "maxItems": .integer(3),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "text": .object([
                                "type": .string("string"),
                                "description": .string("Exact consecutive words copied from targetText, in \(source)")
                            ]),
                            "explanation": .object([
                                "type": .string("string"),
                                "description": .string("Grammar explanation written in \(explanation), concise and accurate. \(languageRule)")
                            ])
                        ]),
                        "required": .array([.string("text"), .string("explanation")])
                    ])
                ]),
                "keyPhrases": .object([
                    "type": .string("array"), "minItems": .integer(minimumItems), "maxItems": .integer(4),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "text": .object([
                                "type": .string("string"),
                                "description": .string("Exact consecutive words copied from targetText, in \(source)")
                            ]),
                            "meaning": .object([
                                "type": .string("string"),
                                "description": .string("Meaning of the phrase written in \(explanation). \(languageRule)")
                            ])
                        ]),
                        "required": .array([.string("text"), .string("meaning")])
                    ])
                ])
            ]),
            "required": .array([.string("translation"), .string("sentenceCore"), .string("grammarPoints"), .string("keyPhrases")])
        ])
    }

    static func deepAnalysis(request: ExplanationRequest) -> SchemaValue {
        let explanation = request.explanationLanguage
        let source = request.sourceLanguage
        let fragment = "Exact consecutive text copied from targetText in \(source); never translate"
        let explained = "Write in \(explanation). \(QwenPrompt.explanationLanguageRule(for: explanation))"
        var required = ["sentenceType", "sentencePattern", "components", "clauses", "grammarPoints", "interpretation"]
        if request.sourceLanguage.localizedCaseInsensitiveContains("Japanese") { required.append("japaneseWords") }
        func string(_ description: String) -> SchemaValue {
            .object(["type": .string("string"), "description": .string(description)])
        }
        let component = SchemaValue.object([
            "type": .string("object"),
            "properties": .object([
                "text": string(fragment), "role": string(explained),
                "explanation": string(explained), "modifies": string("Exact targetText fragment being modified, or empty string")
            ]),
            "required": .array([.string("text"), .string("role"), .string("explanation"), .string("modifies")])
        ])
        let clause = SchemaValue.object([
            "type": .string("object"),
            "properties": .object([
                "text": string(fragment), "type": string(explained),
                "function": string(explained), "explanation": string(explained)
            ]),
            "required": .array([.string("text"), .string("type"), .string("function"), .string("explanation")])
        ])
        let isJapanese = request.sourceLanguage.localizedCaseInsensitiveContains("Japanese")
        let grammar = SchemaValue.object([
            "type": .string("object"),
            "properties": .object(["text": string(fragment), "explanation": string(explained)]),
            "required": .array([.string("text"), .string("explanation")])
        ])
        let japaneseWord = SchemaValue.object([
            "type": .string("object"),
            "properties": .object([
                "text": string(fragment),
                "baseForm": string("Dictionary form; use Japanese orthography"),
                "reading": string("Kana reading; model-provided reference, never HTML"),
                "inflectionType": string(explained),
                "grammaticalFunction": string(explained)
            ]),
            "required": .array([.string("text"), .string("baseForm"), .string("reading"), .string("inflectionType"), .string("grammaticalFunction")])
        ])
        return .object([
            "type": .string("object"),
            "properties": .object([
                "sentenceType": string(explained),
                "sentencePattern": string("Conventional syntax pattern plus a short \(explanation) explanation"),
                "components": .object(["type": .string("array"), "maxItems": .integer(8), "items": component]),
                "clauses": .object(["type": .string("array"), "maxItems": .integer(6), "items": clause]),
                "grammarPoints": .object(["type": .string("array"), "minItems": .integer(isJapanese ? 2 : 0), "maxItems": .integer(6), "items": grammar]),
                "interpretation": string(explained),
                "japaneseWords": .object(["type": .string("array"), "maxItems": .integer(12), "items": japaneseWord])
            ]),
            "required": .array(required.map(SchemaValue.string))
        ])
    }
}

public extension OllamaReadingAI where Client == URLSessionHTTPClient {
    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, model: String = Self.defaultModel, timeout: TimeInterval = 60) {
        self.init(baseURL: baseURL, model: model, client: URLSessionHTTPClient(), timeout: timeout)
    }
}
