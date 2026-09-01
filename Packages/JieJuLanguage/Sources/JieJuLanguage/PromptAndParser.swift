import Foundation

public enum QwenPrompt {
    public static let system = """
    You are a precise language tutor. Explain only TARGET using CONTEXT only for disambiguation. Return JSON only, with exactly these keys:
    {"translation":"natural Chinese translation","sentenceCore":"short subject-verb-object core","grammarPoints":[{"text":"source fragment","explanation":"concise Chinese explanation"}],"keyPhrases":[{"text":"source phrase","meaning":"concise Chinese meaning"}]}
    Use at most 3 grammarPoints and 4 keyPhrases. Never use Markdown.
    """

    public static func user(_ request: ExplanationRequest) -> String {
        """
        SOURCE_LANGUAGE: \(request.sourceLanguage)
        EXPLANATION_LANGUAGE: \(request.explanationLanguage)
        <BEFORE>\(request.precedingContext ?? "")</BEFORE>
        <TARGET>\(request.targetText)</TARGET>
        <AFTER>\(request.followingContext ?? "")</AFTER>
        """
    }

    public static func repair(rawResponse: String) -> String {
        """
        Convert the following failed response into valid JSON matching the exact schema. Do not add commentary or Markdown.
        <FAILED_RESPONSE>\(rawResponse)</FAILED_RESPONSE>
        """
    }
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
