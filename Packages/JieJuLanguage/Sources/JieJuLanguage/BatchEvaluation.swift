import Foundation

public struct BatchInput: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let targetText: String
    public let precedingContext: String?
    public let followingContext: String?
    public let sourceLanguage: String
    public let explanationLanguage: String

    public init(
        id: String,
        category: String,
        targetText: String,
        precedingContext: String? = nil,
        followingContext: String? = nil,
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) {
        self.id = id
        self.category = category
        self.targetText = targetText
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.sourceLanguage = sourceLanguage
        self.explanationLanguage = explanationLanguage
    }

    public var request: ExplanationRequest {
        .init(
            targetText: targetText,
            precedingContext: precedingContext,
            followingContext: followingContext,
            sourceLanguage: sourceLanguage,
            explanationLanguage: explanationLanguage
        )
    }

    public func validated() throws -> Self {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("batch id must not be empty")
        }
        guard !category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("batch category must not be empty")
        }
        _ = try request.validated()
        return self
    }
}

public struct BatchAttempt: Equatable, Sendable {
    public let explanation: Explanation?
    public let error: String?
    public let raw: String?
    public let jsonValid: Bool

    public init(explanation: Explanation? = nil, error: String? = nil, raw: String? = nil, jsonValid: Bool) {
        self.explanation = explanation
        self.error = error
        self.raw = raw
        self.jsonValid = jsonValid
    }
}

public protocol BatchReadingAI: Sendable {
    func attemptExplanation(_ request: ExplanationRequest) async -> BatchAttempt
}

public struct BatchResult: Codable, Equatable, Sendable {
    public let id: String
    public let category: String
    public let explanation: Explanation?
    public let error: String?
    public let raw: String?
    public let elapsedMilliseconds: Int
    public let jsonValid: Bool

    public init(input: BatchInput, attempt: BatchAttempt, elapsedMilliseconds: Int) {
        id = input.id
        category = input.category
        explanation = attempt.explanation
        error = attempt.error
        raw = attempt.raw
        self.elapsedMilliseconds = elapsedMilliseconds
        jsonValid = attempt.jsonValid
    }
}

public struct BatchProcessor<Provider: BatchReadingAI>: Sendable {
    public let provider: Provider
    public init(provider: Provider) { self.provider = provider }

    public func run(_ inputs: [BatchInput]) async -> [BatchResult] {
        var results: [BatchResult] = []
        results.reserveCapacity(inputs.count)
        let clock = ContinuousClock()
        for input in inputs {
            let start = clock.now
            let attempt: BatchAttempt
            do {
                _ = try input.validated()
                attempt = await provider.attemptExplanation(input.request)
            } catch {
                attempt = .init(error: error.localizedDescription, jsonValid: false)
            }
            let duration = start.duration(to: clock.now)
            let milliseconds = max(0, Int(duration.components.seconds * 1_000) + Int(duration.components.attoseconds / 1_000_000_000_000_000))
            results.append(.init(input: input, attempt: attempt, elapsedMilliseconds: milliseconds))
        }
        return results
    }
}

public enum JSONL {
    public static func decodeInputs(_ data: Data) throws -> [BatchInput] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReadingAIError.invalidInput("input JSONL is not UTF-8")
        }
        return try text.split(whereSeparator: \Character.isNewline).enumerated().map { index, line in
            do {
                return try JSONDecoder().decode(BatchInput.self, from: Data(line.utf8))
            } catch {
                throw ReadingAIError.invalidInput("invalid JSONL at line \(index + 1): \(error.localizedDescription)")
            }
        }
    }

    public static func encodeResults(_ results: [BatchResult]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try results.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        return Data((lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).utf8)
    }
}

public enum BatchReport {
    public static func markdown(results: [BatchResult]) -> String {
        let successes = results.filter(\.jsonValid).count
        let successRate = percentage(successes, of: results.count)
        let average = results.isEmpty ? 0 : Double(results.reduce(0) { $0 + $1.elapsedMilliseconds }) / Double(results.count)
        let categories = Dictionary(grouping: results, by: \.category)
        let categoryRows = categories.keys.sorted().map { category -> String in
            let values = categories[category, default: []]
            let passed = values.filter(\.jsonValid).count
            return "| \(escaped(category)) | \(values.count) | \(passed) | \(percentage(passed, of: values.count)) |"
        }.joined(separator: "\n")

        return """
        # JieJu Language Evaluation Report

        ## Automated summary

        - Total: \(results.count)
        - Successful JSON explanations: \(successes)
        - Success rate: \(successRate)
        - Average elapsed: \(String(format: "%.1f", average)) ms

        ## Success by category

        | Category | Total | Successful | Success rate |
        | --- | ---: | ---: | ---: |
        \(categoryRows)

        ## Manual scoring

        Fill these fields after reviewing each result. Leave them blank until a human evaluator has scored the output.

        | ID | Translation accuracy | Sentence-core accuracy | Grammar accuracy | Phrase usefulness | Hallucination | Notes |
        | --- | --- | --- | --- | --- | --- | --- |
        \(results.map { "| \(escaped($0.id)) |  |  |  |  |  |  |" }.joined(separator: "\n"))

        Suggested scoring: accuracy/usefulness fields use 1–5; Hallucination uses Yes/No; Notes capture concrete errors.
        """ + "\n"
    }

    private static func percentage(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0.0%" }
        return String(format: "%.1f%%", Double(value) * 100 / Double(total))
    }

    private static func escaped(_ value: String) -> String { value.replacingOccurrences(of: "|", with: "\\|") }
}
