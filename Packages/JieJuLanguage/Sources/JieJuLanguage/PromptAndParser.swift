import Foundation

public enum QwenPrompt {
    public static let system = """
    You are a language tutor. Analyze targetText only. Context is reference only: never copy context into the answer.
    Translate only these value types: translation, explanation, meaning. Write them in explanationLanguage.
    NEVER translate sentenceCore or any text field. Keep them in sourceLanguage using exact consecutive words copied from targetText.
    Every grammarPoints.text and keyPhrases.text must be copied exactly from targetText. Use empty arrays when unsure.
    Return JSON only. The response schema is supplied separately.
    """

    public static func user(_ request: ExplanationRequest) -> String {
        let payload = PromptInput(
            task: "Explain targetText only",
            outputLanguageRule: explanationLanguageRule(for: request.explanationLanguage),
            sourceLanguage: request.sourceLanguage,
            explanationLanguage: request.explanationLanguage,
            precedingContext: request.precedingContext,
            targetText: request.targetText,
            followingContext: request.followingContext
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(payload)) ?? Data("{}".utf8), as: UTF8.self)
    }

    public static func repair(request: ExplanationRequest, rawResponse: String) -> String {
        _ = rawResponse
        return """
        The previous answer failed validation. Start over and analyze only this targetText: \(request.targetText)
        translation and explanations language: \(request.explanationLanguage)
        \(explanationLanguageRule(for: request.explanationLanguage))
        sentenceCore language: \(request.sourceLanguage)
        translation must be written in \(request.explanationLanguage) and must not be identical to targetText.
        For this retry, set sentenceCore exactly to targetText: \(request.targetText)
        Return 1 to 3 useful grammarPoints and 1 to 4 useful keyPhrases. Every text value must be exact consecutive words copied from targetText; never translate a text value. Return JSON only.
        """
    }

    public static func explanationLanguageRule(for language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chinese", "zh", "zh-hans", "zh-hant":
            return "translation, explanation, and meaning MUST use Chinese characters; do not write full English sentences in these fields."
        case "japanese", "ja":
            return "translation, explanation, and meaning MUST be written in Japanese."
        case "korean", "ko":
            return "translation, explanation, and meaning MUST be written in Korean."
        default:
            return "translation, explanation, and meaning MUST be written in \(language)."
        }
    }
}

private struct PromptInput: Codable {
    let task: String
    let outputLanguageRule: String
    let sourceLanguage: String
    let explanationLanguage: String
    let precedingContext: String?
    let targetText: String
    let followingContext: String?
}

public enum ExplanationParser {
    public static func parse(_ raw: String) throws -> Explanation {
        let cleaned = stripMarkdownFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw ReadingAIError.invalidResponse("response is not UTF-8")
        }
        do {
            let result = try JSONDecoder().decode(Explanation.self, from: data)
            return try result.validated()
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.invalidResponse(error.localizedDescription)
        }
    }

    static func stripMarkdownFence(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        guard lines.count >= 2, lines.first?.hasPrefix("```") == true else { return trimmed }
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

public enum DeepQwenPrompt {
    public static let system = """
    You are a rigorous syntax tutor. Analyze targetText only; context may resolve meaning but must never appear as analyzed text.
    Copy every component.text, component.modifies, clause.text, and grammarPoints.text exactly from consecutive targetText words. Use an empty string when there is no modifies fragment. Explain roles, relationships, and interpretation in explanationLanguage.
    Describe sentencePattern with conventional labels such as S, V, O, C, relative clause, or adverbial clause.
    Use empty clauses when the sentence has no clause structure. Return JSON only using the supplied schema.
    """

    public static func user(_ request: ExplanationRequest) -> String {
        """
        Task: deeply analyze targetText syntax.
        sourceLanguage: \(request.sourceLanguage)
        explanationLanguage: \(request.explanationLanguage)
        \(QwenPrompt.explanationLanguageRule(for: request.explanationLanguage))
        precedingContext: \(request.precedingContext ?? "")
        targetText: \(request.targetText)
        followingContext: \(request.followingContext ?? "")
        """
    }

    public static func repair(_ request: ExplanationRequest) -> String {
        """
        Start over. Analyze only targetText: \(request.targetText)
        Every components.text, non-empty components.modifies, clauses.text, and grammarPoints.text must be exact consecutive text copied from targetText.
        All explanations must be in \(request.explanationLanguage). Use fewer items when uncertain. Return JSON only.
        """
    }
}

public enum DeepAnalysisParser {
    public static func parse(_ raw: String, request: ExplanationRequest) throws -> DeepAnalysis {
        let cleaned = ExplanationParser.stripMarkdownFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else {
            throw ReadingAIError.invalidResponse("response is not UTF-8")
        }
        do {
            return try JSONDecoder().decode(DeepAnalysis.self, from: data).validated(against: request)
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.invalidResponse(error.localizedDescription)
        }
    }
}
