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

    @Test func validatesSourceFragmentsAgainstTargetOnly() throws {
        let request = ExplanationRequest(
            targetText: "Although tired, she continued.",
            precedingContext: "Her friends stopped to rest.",
            followingContext: "They arrived after midnight."
        )
        #expect(try sampleExplanation.validated(against: request) == sampleExplanation)

        let contextPhrase = Explanation(
            translation: "x", sentenceCore: "x",
            grammarPoints: [],
            keyPhrases: [.init(text: "stopped to rest", meaning: "休息")]
        )
        #expect(throws: ReadingAIError.self) { try contextPhrase.validated(against: request) }

        let contextGrammar = Explanation(
            translation: "x", sentenceCore: "x",
            grammarPoints: [.init(text: "after midnight", explanation: "介词短语")],
            keyPhrases: []
        )
        #expect(throws: ReadingAIError.self) { try contextGrammar.validated(against: request) }

        let contextCore = Explanation(
            translation: "x", sentenceCore: "They arrived after midnight",
            grammarPoints: [], keyPhrases: []
        )
        #expect(throws: ReadingAIError.self) { try contextCore.validated(against: request) }

        let partialWord = Explanation(
            translation: "x", sentenceCore: "x", grammarPoints: [],
            keyPhrases: [.init(text: "he", meaning: "他")]
        )
        #expect(throws: ReadingAIError.self) { try partialWord.validated(against: request) }
    }

    @Test func sourceMatchingToleratesCaseWidthAndPunctuation() throws {
        let explanation = Explanation(
            translation: "你好", sentenceCore: "hello world",
            grammarPoints: [.init(text: "HELLO, world", explanation: "问候")],
            keyPhrases: []
        )
        #expect(try explanation.validated(against: .init(targetText: "Hello—world!")) == explanation)
    }

    @Test func rejectsTranslationIdenticalToTarget() {
        let request = ExplanationRequest(targetText: "The train leaves at six.")
        let echo = Explanation(
            translation: "The train leaves at six.", sentenceCore: "The train leaves at six.",
            grammarPoints: [], keyPhrases: []
        )
        #expect(throws: ReadingAIError.self) { try echo.validated(against: request) }

        let caseEcho = Explanation(
            translation: "THE TRAIN LEAVES AT SIX.", sentenceCore: "The train leaves at six.",
            grammarPoints: [], keyPhrases: []
        )
        #expect(throws: ReadingAIError.self) { try caseEcho.validated(against: request) }
    }

    @Test func allowsIdenticalTextWhenLanguagesMatch() throws {
        let request = ExplanationRequest(targetText: "The train leaves at six.", sourceLanguage: "English", explanationLanguage: "English")
        let echo = Explanation(
            translation: "The train leaves at six.", sentenceCore: "The train leaves at six.",
            grammarPoints: [], keyPhrases: []
        )
        #expect(try echo.validated(against: request) == echo)
    }
}

let sampleExplanation = Explanation(
    translation: "虽然很累，她仍继续前行。",
    sentenceCore: "she continued",
    grammarPoints: [.init(text: "Although tired", explanation: "让步状语从句的省略")],
    keyPhrases: [.init(text: "continued", meaning: "继续")]
)
