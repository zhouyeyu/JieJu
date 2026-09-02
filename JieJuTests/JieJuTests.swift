import XCTest
@testable import JieJu

final class JieJuTests: XCTestCase {
    func testProjectFoundationLoads() {
        XCTAssertEqual("JieJu", "JieJu")
    }

    @MainActor
    func testReaderUpdatesExplanationConfigurationWithoutResettingState() async throws {
        let recorder = ExplanationRequestRecorder()
        let model = ReaderViewModel(explanationProvider: MockReaderExplanationProvider())
        let selection = ReaderSelection(
            targetText: "She continued.",
            precedingContext: nil,
            followingContext: nil,
            anchorRect: .zero
        )
        model.updateSelection(selection)

        model.updateExplanationConfiguration(
            provider: RecordingExplanationProvider(recorder: recorder),
            explanationLanguage: "Japanese"
        )
        model.requestExplanation()

        var captured = await recorder.request
        for _ in 0..<100 where captured == nil {
            await Task.yield()
            captured = await recorder.request
        }
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.targetText, selection.targetText)
        XCTAssertEqual(request.explanationLanguage, "Japanese")
        XCTAssertEqual(model.selection, selection)
    }
}

private actor ExplanationRequestRecorder {
    private(set) var request: ReaderExplanationRequest?
    func record(_ request: ReaderExplanationRequest) { self.request = request }
}

private struct RecordingExplanationProvider: ReaderExplanationProviding {
    let recorder: ExplanationRequestRecorder

    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        await recorder.record(request)
        return ReaderExplanation(
            translation: "続けた。",
            sentenceCore: request.targetText,
            grammarPoints: [],
            keyPhrases: []
        )
    }
}
