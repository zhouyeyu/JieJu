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
        #expect(prompt.contains(#""targetText":"TARGET""#))
        #expect(prompt.contains(#""precedingContext":"BEFORE""#))
        #expect(prompt.contains(#""followingContext":"AFTER""#))
        #expect(QwenPrompt.system.contains("never copy context"))
        #expect(QwenPrompt.system.contains("schema is supplied separately"))
    }

    @Test func repairPromptIncludesOriginalInputAndFailedResponse() {
        let request = ExplanationRequest(targetText: "TARGET", precedingContext: "CONTEXT")
        let prompt = QwenPrompt.repair(request: request, rawResponse: "FAILED")
        #expect(prompt.contains("targetText: TARGET"))
        #expect(!prompt.contains("FAILED"))
        #expect(prompt.contains("1 to 3 useful grammarPoints"))
        #expect(!prompt.contains("CONTEXT"))
    }

    @Test func chinesePromptExplicitlyRequiresChineseExplanations() {
        let request = ExplanationRequest(targetText: "She continued.", explanationLanguage: "Chinese")
        let prompt = QwenPrompt.user(request)
        let repair = QwenPrompt.repair(request: request, rawResponse: "bad")
        #expect(prompt.contains("MUST use Chinese characters"))
        #expect(repair.contains("MUST use Chinese characters"))
    }
}

private var validJSON: String { String(decoding: try! JSONEncoder().encode(sampleExplanation), as: UTF8.self) }
