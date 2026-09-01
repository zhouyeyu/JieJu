import Foundation
import Testing
@testable import JieJuLanguage

@Suite struct ParserPromptTests {
    @Test func parsesStrictJSON() throws {
        #expect(try ExplanationParser.parse(validJSON) == sampleExplanation)
    }

    @Test func stripsMarkdownJSONFence() throws {
        #expect(try ExplanationParser.parse("```json\n\(validJSON)\n```") == sampleExplanation)
    }

    @Test func rejectsMissingFieldsTruncationAndLimits() {
        #expect(throws: ReadingAIError.self) { try ExplanationParser.parse(#"{"translation":"x"}"#) }
        #expect(throws: ReadingAIError.self) { try ExplanationParser.parse(#"{"translation":"x"#) }
        let tooMany = Explanation(translation: "x", sentenceCore: "y", grammarPoints: Array(repeating: .init(text: "a", explanation: "b"), count: 4), keyPhrases: [])
        let data = try! JSONEncoder().encode(tooMany)
        #expect(throws: ReadingAIError.self) { try ExplanationParser.parse(String(decoding: data, as: UTF8.self)) }
    }

    @Test func promptClearlySeparatesTargetAndContext() {
        let prompt = QwenPrompt.user(.init(targetText: "TARGET", precedingContext: "BEFORE", followingContext: "AFTER"))
        #expect(prompt.contains("<TARGET>TARGET</TARGET>"))
        #expect(prompt.contains("<BEFORE>BEFORE</BEFORE>"))
        #expect(prompt.contains("<AFTER>AFTER</AFTER>"))
        #expect(QwenPrompt.system.contains("at most 3 grammarPoints and 4 keyPhrases"))
    }
}

private var validJSON: String { String(decoding: try! JSONEncoder().encode(sampleExplanation), as: UTF8.self) }
