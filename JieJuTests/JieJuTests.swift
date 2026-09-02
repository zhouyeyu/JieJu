import XCTest
@testable import JieJu
import JieJuLanguage

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
    func testFuriganaModeDefaultsHiddenAndPersists() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.furiganaDisplayMode, .hidden)
        settings.furiganaDisplayMode = .kanji
        XCTAssertEqual(AppSettings(defaults: defaults).furiganaDisplayMode, .kanji)
    }

    func testEPUBScriptMeasuresBodyColumnsAndExcludesRubyReadingsFromSelection() {
        let script = EPUBWebScript.script(horizontalMargin: 54)

        XCTAssertTrue(script.contains("document.body.scrollWidth"))
        XCTAssertTrue(script.contains("range.cloneContents()"))
        XCTAssertTrue(script.contains("querySelectorAll('rt, rp')"))
        XCTAssertTrue(script.contains("textWithoutReadings(document.body)"))
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

    @MainActor
    func testReaderRequestsDeepAnalysisOnlyOnDemand() async throws {
        let recorder = DeepAnalysisRequestRecorder()
        let model = ReaderViewModel(explanationProvider: RecordingDeepAnalysisProvider(recorder: recorder))
        model.updateSelection(.init(
            targetText: "Although tired, she continued.",
            precedingContext: nil, followingContext: nil, anchorRect: .zero
        ))

        XCTAssertEqual(model.deepAnalysisState, .idle)
        model.requestDeepAnalysis()
        for _ in 0..<100 {
            if case .loaded = model.deepAnalysisState { break }
            await Task.yield()
        }

        let recordedRequest = await recorder.request
        XCTAssertEqual(recordedRequest?.targetText, "Although tired, she continued.")
        guard case let .loaded(result) = model.deepAnalysisState else {
            return XCTFail("Expected loaded deep analysis")
        }
        XCTAssertEqual(result.sentencePattern, "Although + adjective, S + V")
    }

    @MainActor
    func testReaderDetectsJapaneseSelectionForAIRequest() async throws {
        let recorder = ExplanationRequestRecorder()
        let model = ReaderViewModel(explanationProvider: RecordingExplanationProvider(recorder: recorder))
        model.updateSelection(.init(
            targetText: "私は日本語の本を読みます。",
            precedingContext: nil, followingContext: nil, anchorRect: .zero
        ))
        model.requestExplanation()
        var captured = await recorder.request
        for _ in 0..<100 where captured == nil {
            await Task.yield()
            captured = await recorder.request
        }
        XCTAssertEqual(captured?.sourceLanguage, "Japanese")
    }

    func testEPUBFuriganaEntriesKeepOnlyUnambiguousLocalReadings() {
        let provider = StubJapaneseReadingProvider(segments: [
            .init(surface: "今日", reading: "きょう"),
            .init(surface: "と"),
            .init(surface: "今日", reading: "こんにち"),
            .init(surface: "日本語", reading: "にほんご")
        ])
        let xhtml = "<html><body><p>今日と日本語</p><ruby>本<rt>ほん</rt></ruby></body></html>"
        let entries = EPUBFuriganaInjection.entries(for: xhtml, provider: provider)
        XCTAssertEqual(entries, [.init(surface: "日本語", reading: "にほんご")])
        let script = EPUBFuriganaInjection.script(for: xhtml, provider: provider)
        XCTAssertTrue(script.contains("closest('ruby, rt, script, style, head, textarea')"))
        XCTAssertTrue(script.contains("DOMContentLoaded"))
    }
}

private struct StubJapaneseReadingProvider: JapaneseReadingProviding {
    let segments: [ReadingSegment]
    func segments(for text: String) -> [ReadingSegment] { segments }
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

private actor DeepAnalysisRequestRecorder {
    private(set) var request: ReaderExplanationRequest?
    func record(_ request: ReaderExplanationRequest) { self.request = request }
}

private struct RecordingDeepAnalysisProvider: ReaderExplanationProviding {
    let recorder: DeepAnalysisRequestRecorder

    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        ReaderExplanation(translation: "", sentenceCore: "", grammarPoints: [], keyPhrases: [])
    }

    func analyzeDeep(_ request: ReaderExplanationRequest) async throws -> ReaderDeepAnalysis {
        await recorder.record(request)
        return ReaderDeepAnalysis(
            sentenceType: "简单句",
            sentencePattern: "Although + adjective, S + V",
            components: [], clauses: [], grammarPoints: [], interpretation: "尽管疲惫，她仍继续。",
            japaneseWords: []
        )
    }
}
