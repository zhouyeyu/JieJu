import Foundation

public enum QwenPrompt {
    public static let system = """
    You are a precise language tutor. Explain only targetText. Use context only to resolve meaning and references. Follow explanationLanguage for translation and explanations; keep quoted source fragments in sourceLanguage. Return JSON only, with exactly these keys:
    {"translation":"natural translation","sentenceCore":"short source-language subject-verb-object core","grammarPoints":[{"text":"exact source fragment","explanation":"concise explanation"}],"keyPhrases":[{"text":"exact source phrase","meaning":"concise meaning"}]}
    Use at most 3 grammarPoints and 4 keyPhrases. Do not invent phrases absent from targetText. Never use Markdown or extra keys.
    """

    public static func user(_ request: ExplanationRequest) -> String {
        let payload = PromptInput(
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

    public static func repair(rawResponse: String) -> String {
        """
        Convert the following failed response into valid JSON matching the exact schema. Do not add commentary or Markdown.
        <FAILED_RESPONSE>\(rawResponse)</FAILED_RESPONSE>
        """
    }
}

private struct PromptInput: Codable {
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
