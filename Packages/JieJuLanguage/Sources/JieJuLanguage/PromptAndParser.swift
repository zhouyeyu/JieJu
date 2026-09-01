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
        sentenceCore language: \(request.sourceLanguage)
        For this retry, set sentenceCore exactly to targetText: \(request.targetText)
        For this retry, grammarPoints MUST be [] and keyPhrases MUST be []. Only produce a reliable translation. Return JSON only.
        """
    }
}

private struct PromptInput: Codable {
    let task: String
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
