import Foundation

public struct ExplanationRequest: Codable, Equatable, Sendable {
    public let targetText: String
    public let precedingContext: String?
    public let followingContext: String?
    public let sourceLanguage: String
    public let explanationLanguage: String

    public init(
        targetText: String,
        precedingContext: String? = nil,
        followingContext: String? = nil,
        sourceLanguage: String = "English",
        explanationLanguage: String = "Chinese"
    ) {
        self.targetText = targetText
        self.precedingContext = precedingContext
        self.followingContext = followingContext
        self.sourceLanguage = sourceLanguage
        self.explanationLanguage = explanationLanguage
    }

    public func validated(limits: InputLimits = .default) throws -> Self {
        guard !targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("targetText must not be empty")
        }
        guard targetText.count <= limits.targetText else {
            throw ReadingAIError.invalidInput("targetText exceeds \(limits.targetText) characters")
        }
        for (name, value) in [("precedingContext", precedingContext), ("followingContext", followingContext)] {
            if let value, value.count > limits.context {
                throw ReadingAIError.invalidInput("\(name) exceeds \(limits.context) characters")
            }
        }
        guard !sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !explanationLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReadingAIError.invalidInput("language names must not be empty")
        }
        return self
    }
}

public struct InputLimits: Equatable, Sendable {
    public let targetText: Int
    public let context: Int
    public init(targetText: Int, context: Int) {
        self.targetText = targetText
        self.context = context
    }
    public static let `default` = InputLimits(targetText: 2_000, context: 2_000)
}

public struct GrammarPoint: Codable, Equatable, Sendable {
    public let text: String
    public let explanation: String
    public init(text: String, explanation: String) {
        self.text = text
        self.explanation = explanation
    }
}

public struct KeyPhrase: Codable, Equatable, Sendable {
    public let text: String
    public let meaning: String
    public init(text: String, meaning: String) {
        self.text = text
        self.meaning = meaning
    }
}

public struct Explanation: Codable, Equatable, Sendable {
    public let translation: String
    public let sentenceCore: String
    public let grammarPoints: [GrammarPoint]
    public let keyPhrases: [KeyPhrase]

    public init(translation: String, sentenceCore: String, grammarPoints: [GrammarPoint], keyPhrases: [KeyPhrase]) {
        self.translation = translation
        self.sentenceCore = sentenceCore
        self.grammarPoints = grammarPoints
        self.keyPhrases = keyPhrases
    }

    public func validated() throws -> Self {
        guard !translation.isBlank, !sentenceCore.isBlank else {
            throw ReadingAIError.invalidResponse("translation and sentenceCore must not be empty")
        }
        guard grammarPoints.count <= 3, keyPhrases.count <= 4 else {
            throw ReadingAIError.invalidResponse("response exceeds item limits")
        }
        guard grammarPoints.allSatisfy({ !$0.text.isBlank && !$0.explanation.isBlank }),
              keyPhrases.allSatisfy({ !$0.text.isBlank && !$0.meaning.isBlank }) else {
            throw ReadingAIError.invalidResponse("response contains empty items")
        }
        return self
    }

    public func validated(against request: ExplanationRequest) throws -> Self {
        _ = try validated()
        let target = request.targetText.matchableSourceText

        for point in grammarPoints {
            let fragment = point.text.matchableSourceText
            guard !fragment.isEmpty, " \(target) ".contains(" \(fragment) ") else {
                throw ReadingAIError.invalidResponse("grammar fragment is absent from targetText: \(point.text)")
            }
        }
        for phrase in keyPhrases {
            let fragment = phrase.text.matchableSourceText
            guard !fragment.isEmpty, " \(target) ".contains(" \(fragment) ") else {
                throw ReadingAIError.invalidResponse("key phrase is absent from targetText: \(phrase.text)")
            }
        }
        return self
    }
}

public protocol ReadingAI: Sendable {
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}

public enum ReadingAIError: Error, Equatable, Sendable {
    case invalidInput(String)
    case serviceUnavailable(String)
    case modelMissing(String)
    case timeout
    case transport(String)
    case invalidResponse(String)
}

extension ReadingAIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidInput(let message): "Invalid input: \(message)"
        case .serviceUnavailable(let message): "Ollama unavailable: \(message)"
        case .modelMissing(let model): "Model is not installed: \(model)"
        case .timeout: "The Ollama request timed out"
        case .transport(let message): "Network error: \(message)"
        case .invalidResponse(let message): "Invalid model response: \(message)"
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var matchableSourceText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .split(whereSeparator: { $0 == " " })
            .map(String.init)
            .joined(separator: " ")
    }
}
