import Foundation
import Testing
@testable import JieJuLanguage

@Suite struct DomainTests {
    @Test func requestAndExplanationCodableRoundTrip() throws {
        let request = ExplanationRequest(targetText: "Although tired, she continued.", precedingContext: "It was late.", followingContext: "She finished.")
        let requestData = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ExplanationRequest.self, from: requestData) == request)

        let explanation = sampleExplanation
        let data = try JSONEncoder().encode(explanation)
        #expect(try JSONDecoder().decode(Explanation.self, from: data) == explanation)
    }

    @Test func rejectsBlankAndOversizedInput() {
        #expect(throws: ReadingAIError.invalidInput("targetText must not be empty")) {
            try ExplanationRequest(targetText: "  ").validated()
        }
        #expect(throws: ReadingAIError.self) {
            try ExplanationRequest(targetText: "1234").validated(limits: .init(targetText: 3, context: 3))
        }
        #expect(throws: ReadingAIError.self) {
            try ExplanationRequest(targetText: "ok", precedingContext: "1234").validated(limits: .init(targetText: 3, context: 3))
        }
    }

    @Test func mockIsDeterministic() async throws {
        let request = ExplanationRequest(targetText: "Hello")
        let first = try await MockReadingAI().explain(request)
        let second = try await MockReadingAI().explain(request)
        #expect(first == second)
    }
}

let sampleExplanation = Explanation(
    translation: "虽然很累，她仍继续前行。",
    sentenceCore: "she continued",
    grammarPoints: [.init(text: "Although tired", explanation: "让步状语从句的省略")],
    keyPhrases: [.init(text: "continue", meaning: "继续")]
)
