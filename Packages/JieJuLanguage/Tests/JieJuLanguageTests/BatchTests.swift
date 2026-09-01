import Foundation
import Testing
@testable import JieJuLanguage

actor BatchStub: BatchReadingAI {
    private var attempts: [BatchAttempt]
    private(set) var received: [ExplanationRequest] = []

    init(_ attempts: [BatchAttempt]) { self.attempts = attempts }

    func attemptExplanation(_ request: ExplanationRequest) async -> BatchAttempt {
        received.append(request)
        guard !attempts.isEmpty else { return .init(error: "missing stub", jsonValid: false) }
        return attempts.removeFirst()
    }
}

@Suite struct BatchTests {
    @Test func parsesBatchCLI() throws {
        let options = try BatchCLIOptions(arguments: [
            "batch", "--input", "in.jsonl", "--output", "out.jsonl", "--report", "report.md",
            "--model", "custom", "--url", "http://localhost:9999"
        ])
        #expect(options.input == "in.jsonl")
        #expect(options.output == "out.jsonl")
        #expect(options.report == "report.md")
        #expect(options.model == "custom")
        #expect(options.baseURL.port == 9999)
    }

    @Test func rejectsIncompleteDuplicateAndUnknownBatchCLI() {
        #expect(throws: ReadingAIError.self) { try BatchCLIOptions(arguments: ["batch", "--input", "in"]) }
        #expect(throws: ReadingAIError.self) { try BatchCLIOptions(arguments: ["batch", "--wat", "x"]) }
        #expect(throws: ReadingAIError.self) {
            try BatchCLIOptions(arguments: ["batch", "--input", "a", "--input", "b", "--output", "o", "--report", "r"])
        }
    }

    @Test func JSONLRoundTripUsesFlattenedRequestFields() throws {
        let text = """
        {"id":"one","category":"simple","targetText":"Hello","sourceLanguage":"English","explanationLanguage":"Chinese"}
        {"id":"two","category":"context","targetText":"It works.","precedingContext":"Before.","followingContext":"After.","sourceLanguage":"English","explanationLanguage":"Chinese"}

        """
        let inputs = try JSONL.decodeInputs(Data(text.utf8))
        #expect(inputs.count == 2)
        #expect(inputs[1].request.precedingContext == "Before.")

        let result = BatchResult(input: inputs[0], attempt: .init(explanation: sampleExplanation, raw: "{}", jsonValid: true), elapsedMilliseconds: 12)
        let encoded = try JSONL.encodeResults([result])
        let line = try #require(String(data: encoded, encoding: .utf8)?.split(separator: "\n").first)
        let decoded = try JSONDecoder().decode(BatchResult.self, from: Data(line.utf8))
        #expect(decoded == result)
    }

    @Test func rejectsMalformedJSONLWithLineNumber() {
        #expect(throws: ReadingAIError.self) {
            try JSONL.decodeInputs(Data("{bad}\n".utf8))
        }
    }

    @Test func processorContinuesAfterFailureAndInvalidInput() async {
        let successful = BatchAttempt(explanation: sampleExplanation, raw: "valid", jsonValid: true)
        let failed = BatchAttempt(error: "offline", raw: "bad", jsonValid: false)
        let stub = BatchStub([successful, failed])
        let inputs = [
            BatchInput(id: "1", category: "simple", targetText: "One"),
            BatchInput(id: "2", category: "simple", targetText: "Two"),
            BatchInput(id: "3", category: "invalid", targetText: "   ")
        ]
        let results = await BatchProcessor(provider: stub).run(inputs)
        #expect(results.count == 3)
        #expect(results[0].jsonValid)
        #expect(results[1].error == "offline")
        #expect(results[1].raw == "bad")
        #expect(!results[2].jsonValid)
        #expect(results[2].error?.contains("targetText") == true)
        #expect(await stub.received.count == 2)
    }

    @Test func reportSummarizesOverallAndCategoryRates() {
        let inputs = [
            BatchInput(id: "1", category: "simple", targetText: "One"),
            BatchInput(id: "2", category: "simple", targetText: "Two"),
            BatchInput(id: "3", category: "context", targetText: "Three")
        ]
        let results = [
            BatchResult(input: inputs[0], attempt: .init(explanation: sampleExplanation, raw: "{}", jsonValid: true), elapsedMilliseconds: 10),
            BatchResult(input: inputs[1], attempt: .init(error: "bad", raw: "x", jsonValid: false), elapsedMilliseconds: 20),
            BatchResult(input: inputs[2], attempt: .init(explanation: sampleExplanation, raw: "{}", jsonValid: true), elapsedMilliseconds: 30)
        ]
        let report = BatchReport.markdown(results: results)
        #expect(report.contains("- Total: 3"))
        #expect(report.contains("- Success rate: 66.7%"))
        #expect(report.contains("- Average elapsed: 20.0 ms"))
        #expect(report.contains("| simple | 2 | 1 | 50.0% |"))
        #expect(report.contains("Translation accuracy"))
        #expect(report.contains("| 1 |  |  |  |  |  |  |"))
    }
}
