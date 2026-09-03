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

        let languagesDiffer = request.explanationLanguage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(request.sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame
        if languagesDiffer, translation.matchableSourceText == target {
            throw ReadingAIError.invalidResponse("translation is not in \(request.explanationLanguage): \(translation)")
        }

        let core = sentenceCore.matchableSourceText
        let targetWords = Set(target.split(separator: " "))
        let coreWords = Set(core.split(separator: " "))
        let coreIsPresent = request.usesUnspacedSourceMatching
            ? request.targetText.unspacedMatchableText.contains(sentenceCore.unspacedMatchableText)
            : (!coreWords.isEmpty && coreWords.isSubset(of: targetWords))
        guard coreIsPresent else {
            throw ReadingAIError.invalidResponse("sentenceCore is absent from targetText: \(sentenceCore)")
        }

        for point in grammarPoints {
            let fragment = point.text.matchableSourceText
            guard !fragment.isEmpty, request.containsSourceFragment(point.text) else {
                throw ReadingAIError.invalidResponse("grammar fragment is absent from targetText: \(point.text)")
            }
        }
        for phrase in keyPhrases {
            let fragment = phrase.text.matchableSourceText
            guard !fragment.isEmpty, request.containsSourceFragment(phrase.text) else {
                throw ReadingAIError.invalidResponse("key phrase is absent from targetText: \(phrase.text)")
            }
        }
        return self
    }
}

public protocol ReadingAI: Sendable {
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}

public protocol StreamingReadingAI: ReadingAI {
    /// Intermediate values are display-only. The last value is fully decoded and validated.
    func explanationStream(_ request: ExplanationRequest) async throws -> AsyncThrowingStream<Explanation, Error>
}

public struct SentenceComponent: Codable, Equatable, Sendable {
    public let text: String
    public let role: String
    public let explanation: String
    public let modifies: String?

    public init(text: String, role: String, explanation: String, modifies: String? = nil) {
        self.text = text
        self.role = role
        self.explanation = explanation
        self.modifies = modifies
    }
}

public struct ClauseExplanation: Codable, Equatable, Sendable {
    public let text: String
    public let type: String
    public let function: String
    public let explanation: String

    public init(text: String, type: String, function: String, explanation: String) {
        self.text = text
        self.type = type
        self.function = function
        self.explanation = explanation
    }
}

public struct DeepAnalysis: Codable, Equatable, Sendable {
    public let sentenceType: String
    public let sentencePattern: String
    public let components: [SentenceComponent]
    public let clauses: [ClauseExplanation]
    public let grammarPoints: [GrammarPoint]
    public let interpretation: String
    public let japaneseWords: [JapaneseWordAnalysis]?

    public init(
        sentenceType: String,
        sentencePattern: String,
        components: [SentenceComponent],
        clauses: [ClauseExplanation],
        grammarPoints: [GrammarPoint],
        interpretation: String,
        japaneseWords: [JapaneseWordAnalysis]? = nil
    ) {
        self.sentenceType = sentenceType
        self.sentencePattern = sentencePattern
        self.components = components
        self.clauses = clauses
        self.grammarPoints = grammarPoints
        self.interpretation = interpretation
        self.japaneseWords = japaneseWords
    }

    public func validated(against request: ExplanationRequest) throws -> Self {
        guard !sentenceType.isBlank, !sentencePattern.isBlank, !interpretation.isBlank else {
            throw ReadingAIError.invalidResponse("deep analysis contains empty summary fields")
        }
        guard components.count <= 8, clauses.count <= 6, grammarPoints.count <= 6 else {
            throw ReadingAIError.invalidResponse("deep analysis exceeds item limits")
        }
        guard (japaneseWords?.count ?? 0) <= 12 else {
            throw ReadingAIError.invalidResponse("deep analysis exceeds Japanese word limit")
        }
        let modifiers = components.compactMap(\.modifies).filter { !$0.isBlank }
        let fragments = components.map(\.text) + modifiers + clauses.map(\.text) + grammarPoints.map(\.text)
        for text in fragments {
            let fragment = text.matchableSourceText
            guard !fragment.isEmpty, request.containsSourceFragment(text) else {
                throw ReadingAIError.invalidResponse("analysis fragment is absent from targetText: \(text)")
            }
        }
        for word in japaneseWords ?? [] {
            let fragment = word.text.matchableSourceText
            guard !fragment.isEmpty, request.containsSourceFragment(word.text),
                  !word.baseForm.isBlank, !word.reading.isBlank,
                  !word.inflectionType.isBlank, !word.grammaticalFunction.isBlank else {
                throw ReadingAIError.invalidResponse("invalid Japanese word analysis: \(word.text)")
            }
        }
        guard components.allSatisfy({ !$0.role.isBlank && !$0.explanation.isBlank }),
              clauses.allSatisfy({ !$0.type.isBlank && !$0.function.isBlank && !$0.explanation.isBlank }),
              grammarPoints.allSatisfy({ !$0.explanation.isBlank }) else {
            throw ReadingAIError.invalidResponse("deep analysis contains empty items")
        }
        return self
    }
}

public protocol DeepReadingAI: Sendable {
    func analyzeDeep(_ request: ExplanationRequest) async throws -> DeepAnalysis
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
        case .serviceUnavailable(let message): "AI service unavailable: \(message)"
        case .modelMissing(let model): "Model is not installed: \(model)"
        case .timeout: "The AI request timed out"
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

    var unspacedMatchableText: String { matchableSourceText.replacingOccurrences(of: " ", with: "") }
}

extension ExplanationRequest {
    var usesUnspacedSourceMatching: Bool {
        sourceLanguage.localizedCaseInsensitiveContains("Japanese") ||
        targetText.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    func containsSourceFragment(_ fragment: String) -> Bool {
        if usesUnspacedSourceMatching {
            let needle = fragment.unspacedMatchableText
            return !needle.isEmpty && targetText.unspacedMatchableText.contains(needle)
        }
        return " \(targetText.matchableSourceText) ".contains(" \(fragment.matchableSourceText) ")
    }
}
