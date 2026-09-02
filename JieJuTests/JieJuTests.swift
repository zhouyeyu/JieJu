import XCTest
@testable import JieJu

final class JieJuTests: XCTestCase {
    func testProjectFoundationLoads() {
        XCTAssertEqual("JieJu", "JieJu")
    }

    @MainActor
    func testLegacyMockSettingMigratesToRealLocalModelOnce() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("mock", forKey: "ai.provider")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.provider, .ollama)
        XCTAssertEqual(defaults.string(forKey: "ai.provider"), "ollama")
        XCTAssertTrue(defaults.bool(forKey: "ai.didMigrateToLocalModelDefault"))
    }

    @MainActor
    func testExplicitMockChoiceIsPreservedAfterMigration() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ai.didMigrateToLocalModelDefault")
        defaults.set("mock", forKey: "ai.provider")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.provider, .mock)
    }

    @MainActor
    func testExplanationPresentationModeDefaultsToSidebarAndPersists() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.explanationPresentationMode, .sidebar)

        settings.explanationPresentationMode = .popover

        let restoredSettings = AppSettings(defaults: defaults)
        XCTAssertEqual(restoredSettings.explanationPresentationMode, .popover)
    }

    @MainActor
    func testEPUBReadingStyleDefaultsAndPersists() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.epubFontSize, 18)
        XCTAssertEqual(settings.epubLineHeight, 1.75)
        XCTAssertEqual(settings.epubHorizontalMargin, 54)

        settings.epubFontSize = 22
        settings.epubLineHeight = 1.9
        settings.epubHorizontalMargin = 64
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.epubFontSize, 22)
        XCTAssertEqual(restored.epubLineHeight, 1.9)
        XCTAssertEqual(restored.epubHorizontalMargin, 64)
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
