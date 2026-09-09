import XCTest
@testable import JieJu
import JieJuLanguage

final class JieJuTests: XCTestCase {
    func testReviewRatingsDescribeFamiliarityWithoutJudgment() {
        XCTAssertEqual(ReviewRating.allCases.map(\.title), ["没想起", "有点模糊", "想起来了", "很熟悉"])
    }

    func testProjectFoundationLoads() {
        XCTAssertEqual("JieJu", "JieJu")
    }

    func testPersistenceLibraryKeepsStableV5CodingKeys() throws {
        XCTAssertEqual(PersistenceLibrary.currentSchemaVersion, 5)
        let encoded = try JSONEncoder().encode(PersistenceLibrary())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set([
            "schemaVersion", "readingProgress", "savedExplanations", "vocabularyEntries", "reviewCards", "reviewLogs"
        ]))
    }

    func testReviewSchedulerProgressesAndHandlesLapse() {
        let scheduler = JieJuReviewScheduler()
        let start = Date(timeIntervalSince1970: 1_704_164_645)
        let original = ReviewCard(vocabularyEntryID: UUID(), dueAt: start, createdAt: start, updatedAt: start)

        let first = scheduler.review(original, rating: .good, at: start)
        XCTAssertEqual(first.card.state, .review)
        XCTAssertEqual(first.card.intervalDays, 2)
        XCTAssertEqual(first.card.dueAt, start.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(first.log.schedulerVersion, "jieju-interval-v1")

        let second = scheduler.review(first.card, rating: .good, at: first.card.dueAt)
        XCTAssertEqual(second.card.intervalDays, 5)

        let lapse = scheduler.review(second.card, rating: .again, at: second.card.dueAt)
        XCTAssertEqual(lapse.card.state, .learning)
        XCTAssertEqual(lapse.card.dueAt, second.card.dueAt.addingTimeInterval(10 * 60))
        XCTAssertEqual(lapse.card.lapses, 1)
        XCTAssertEqual(lapse.card.repetitions, 0)
    }

    func testSelectionClassifierDistinguishesEnglishIntent() {
        XCTAssertEqual(ReaderSelectionClassifier.classify("continued", sourceLanguage: "English"), .word)
        XCTAssertEqual(ReaderSelectionClassifier.classify("look forward to", sourceLanguage: "English"), .expression)
        XCTAssertEqual(ReaderSelectionClassifier.classify("She kept going", sourceLanguage: "English"), .sentence)
        XCTAssertEqual(ReaderSelectionClassifier.classify("She continued.", sourceLanguage: "English"), .sentence)
        XCTAssertEqual(
            ReaderSelectionClassifier.classify("She stopped. Then she listened.", sourceLanguage: "English"),
            .passage
        )
    }

    func testSelectionClassifierUsesJapaneseMorphology() {
        XCTAssertEqual(ReaderSelectionClassifier.classify("飛行機", sourceLanguage: "Japanese"), .word)
        XCTAssertEqual(ReaderSelectionClassifier.classify("読みました", sourceLanguage: "Japanese"), .word)
        XCTAssertEqual(ReaderSelectionClassifier.classify("本を読む", sourceLanguage: "Japanese"), .sentence)
        XCTAssertEqual(ReaderSelectionClassifier.classify("僕は三十七歳で", sourceLanguage: "Japanese"), .ambiguous)
        XCTAssertEqual(ReaderSelectionClassifier.classify("私は本を読みました。", sourceLanguage: "Japanese"), .sentence)
    }

    func testSelectionKindOnlyOffersDirectVocabularySaveForLexicalContent() {
        XCTAssertTrue(ReaderSelectionKind.word.canSaveSelectionAsVocabulary)
        XCTAssertTrue(ReaderSelectionKind.expression.canSaveSelectionAsVocabulary)
        XCTAssertFalse(ReaderSelectionKind.sentence.canSaveSelectionAsVocabulary)
        XCTAssertFalse(ReaderSelectionKind.ambiguous.canSaveSelectionAsVocabulary)
    }

    func testSelectionBoundarySuggestsCompleteJapaneseAndEnglishTokensConservatively() {
        XCTAssertEqual(
            ReaderSelectionBoundarySuggester.suggestion(
                for: "行機", in: "その巨大な飛行機は雨雲を抜けた。", sourceLanguage: "Japanese"
            ),
            .init(originalText: "行機", suggestedText: "飛行機")
        )
        XCTAssertEqual(
            ReaderSelectionBoundarySuggester.suggestion(
                for: "ontinu", in: "She continued walking.", sourceLanguage: "English"
            ),
            .init(originalText: "ontinu", suggestedText: "continued")
        )
        XCTAssertNil(ReaderSelectionBoundarySuggester.suggestion(
            for: "飛行機", in: "飛行機と飛行機", sourceLanguage: "Japanese"
        ))
        XCTAssertNil(ReaderSelectionBoundarySuggester.suggestion(
            for: "飛行機は", in: "その飛行機は着陸した。", sourceLanguage: "Japanese"
        ))
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
    func testCloudSettingsPersistButAPIKeyUsesCredentialStore() {
        let suite = "JieJuTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let credentials = MemoryAPIKeyStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "ai.didMigrateToLocalModelDefault")

        let settings = AppSettings(defaults: defaults, apiKeyStore: credentials)
        settings.provider = .cloud
        settings.cloudURL = "https://example.com/v1"
        settings.cloudModelName = "test-model"
        settings.cloudAPIKey = "sk-private"

        let restored = AppSettings(defaults: defaults, apiKeyStore: credentials)
        XCTAssertEqual(restored.provider, .cloud)
        XCTAssertEqual(restored.cloudURL, "https://example.com/v1")
        XCTAssertEqual(restored.cloudModelName, "test-model")
        XCTAssertEqual(restored.cloudAPIKey, "sk-private")
        XCTAssertNil(defaults.string(forKey: "ai.cloudAPIKey"))
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
        XCTAssertEqual(settings.epubReaderTheme, .paper)

        settings.epubFontSize = 22
        settings.epubLineHeight = 1.9
        settings.epubHorizontalMargin = 64
        settings.epubReaderTheme = .sepia
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.epubFontSize, 22)
        XCTAssertEqual(restored.epubLineHeight, 1.9)
        XCTAssertEqual(restored.epubHorizontalMargin, 64)
        XCTAssertEqual(restored.epubReaderTheme, .sepia)
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
        XCTAssertTrue(script.contains("window.scrollTo"))
        XCTAssertTrue(script.contains("range.cloneContents()"))
        XCTAssertTrue(script.contains("querySelectorAll('rt, rp')"))
        XCTAssertTrue(script.contains("textWithoutReadings(document.body)"))
        XCTAssertTrue(script.contains("makeReadingsPresentationOnly"))
        XCTAssertTrue(script.contains("data-jieju-reading"))
        XCTAssertTrue(script.contains("rt.textContent = ''"))
        XCTAssertTrue(script.contains("selection.removeAllRanges()"))
        XCTAssertTrue(script.contains("anchorForRange"))
        XCTAssertTrue(script.contains("range.intersectsNode"))
        XCTAssertTrue(script.contains("textAnchor: this.anchorForRange(range)"))
    }

    func testEPUBScriptWaitsForStablePaginationAndPreservesTextAnchor() {
        let script = EPUBWebScript.script(horizontalMargin: 54)

        XCTAssertTrue(script.contains("layoutAttempts"))
        XCTAssertTrue(script.contains("textLength > 1200"))
        XCTAssertTrue(script.contains("captureAnchor"))
        XCTAssertTrue(script.contains("pageForAnchor"))
        XCTAssertTrue(script.contains("readableTextNodes"))
        XCTAssertTrue(script.contains("textOffset"))
        XCTAssertTrue(script.contains("textQuote"))
        XCTAssertTrue(script.contains("#jieju-location-"))
        XCTAssertTrue(script.contains("normalizedTextOffset"))
        XCTAssertTrue(script.contains("paginationResult(count, preservedAnchor)"))
        XCTAssertTrue(script.contains("locationAnchor: null"))
        XCTAssertTrue(script.contains("this.locationAnchor = anchor"))
        XCTAssertTrue(script.contains("this.pendingAnchor || this.locationAnchor"))
        XCTAssertTrue(script.contains("forceLayout"))
        XCTAssertTrue(script.contains("range.getClientRects()"))
        XCTAssertTrue(script.contains("lastPage < this.page"))
        XCTAssertTrue(script.contains("requestAnimationFrame"))
    }

    func testEPUBInjectionBuildsPaginatedBodyViewportForLongChapter() {
        let paragraphs = Array(repeating: "<p>This is a long paragraph for testing real EPUB pagination. It must flow into following book pages instead of becoming one chapter-sized page.</p>", count: 100).joined()
        let xhtml = "<html><head><title>Long chapter</title></head><body><h1>Chapter</h1>\(paragraphs)</body></html>"
        let handler = EPUBSchemeHandler(
            resources: [:],
            readingStyle: EPUBReadingStyle(fontSize: 18, lineHeight: 1.75, horizontalMargin: 54)
        )
        let renderedHTML = String(data: handler.injectedXHTML(Data(xhtml.utf8)), encoding: .utf8)!

        XCTAssertTrue(renderedHTML.contains("body { box-sizing: border-box !important"))
        XCTAssertTrue(renderedHTML.contains("column-width: calc(100vw - 108.0px)"))
        XCTAssertTrue(renderedHTML.contains("overflow: hidden !important"))
        XCTAssertFalse(renderedHTML.contains("while (document.body.firstChild)"))
        XCTAssertTrue(renderedHTML.contains("document.fonts.ready"))
        XCTAssertTrue(renderedHTML.contains(paragraphs))
    }

    func testEPUBThemesInjectExplicitForegroundAndBackgroundColors() {
        for theme in EPUBReaderTheme.allCases {
            let handler = EPUBSchemeHandler(
                resources: [:],
                readingStyle: EPUBReadingStyle(theme: theme)
            )
            let xhtml = Data("<html><head></head><body><p style='color:white'>Readable</p></body></html>".utf8)
            let renderedHTML = String(data: handler.injectedXHTML(xhtml), encoding: .utf8)!

            XCTAssertTrue(renderedHTML.contains("background: \(theme.backgroundCSS) !important"))
            XCTAssertTrue(renderedHTML.contains("body * { color: \(theme.foregroundCSS) !important"))
            XCTAssertTrue(renderedHTML.contains("font-size: 18.0px !important"))
            XCTAssertTrue(renderedHTML.contains("line-height: 1.75 !important"))
            XCTAssertTrue(renderedHTML.contains("rt[data-jieju-reading]::before"))
        }
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
            vocabularyProvider: MockReaderVocabularyProvider(),
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

    @MainActor
    func testReaderPublishesStreamingPreviewBeforeFinalResult() async throws {
        let model = ReaderViewModel(explanationProvider: ProgressiveExplanationProvider())
        model.updateSelection(.init(
            targetText: "She continued.", precedingContext: nil, followingContext: nil, anchorRect: .zero
        ))
        model.requestExplanation()

        for _ in 0..<100 {
            if case .streaming = model.explanationState { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard case let .streaming(preview) = model.explanationState else {
            return XCTFail("Expected an intermediate streaming state")
        }
        XCTAssertEqual(preview.translation, "她继续")
        XCTAssertTrue(preview.grammarPoints.isEmpty)

        for _ in 0..<200 {
            if case .loaded = model.explanationState { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        guard case let .loaded(final) = model.explanationState else {
            return XCTFail("Expected a final loaded state")
        }
        XCTAssertEqual(final.translation, "她继续了。")
        XCTAssertEqual(final.grammarPoints, ["continued：一般过去时"])
    }

    @MainActor
    func testReaderUsesDedicatedVocabularyProviderWithContainingSentence() async throws {
        let recorder = WordRequestRecorder()
        let model = ReaderViewModel(vocabularyProvider: RecordingVocabularyProvider(recorder: recorder))
        model.updateSelection(.init(
            targetText: "continued",
            containingSentence: "She continued walking despite the rain.",
            precedingContext: "The path was difficult.",
            followingContext: "Soon she arrived.",
            anchorRect: .zero
        ))

        model.requestExplanation()
        for _ in 0..<100 {
            if case .loaded = model.wordExplanationState { break }
            await Task.yield()
        }

        let request = await recorder.request
        XCTAssertEqual(request?.selectedText, "continued")
        XCTAssertEqual(request?.sentenceContext, "She continued walking despite the rain.")
        XCTAssertEqual(model.explanationState, .idle)
        guard case let .loaded(result) = model.wordExplanationState else {
            return XCTFail("Expected dedicated word explanation")
        }
        XCTAssertEqual(result.lemma, "continue")
        XCTAssertEqual(result.contextualMeaning, "继续走")
    }

    @MainActor
    func testReaderCanAcceptBoundarySuggestionWithoutChangingOriginalSelection() async throws {
        let recorder = WordRequestRecorder()
        let model = ReaderViewModel(
            vocabularyProvider: RecordingVocabularyProvider(recorder: recorder),
            sourceLanguage: "Japanese"
        )
        let selection = ReaderSelection(
            targetText: "行機",
            containingSentence: "その巨大な飛行機は雨雲を抜けた。",
            anchorRect: .zero
        )
        model.updateSelection(selection)

        XCTAssertEqual(model.selectionBoundarySuggestion?.suggestedText, "飛行機")
        model.requestExplanation(targetText: "飛行機")
        for _ in 0..<100 where await recorder.request == nil { await Task.yield() }

        let capturedRequest = await recorder.request
        XCTAssertEqual(capturedRequest?.selectedText, "飛行機")
        XCTAssertEqual(model.selection?.targetText, "行機")
        XCTAssertEqual(model.effectiveSelectionText, "飛行機")
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

    func testEPUBFuriganaPolicyHonorsExplicitDocumentAndChapterLanguages() {
        let japanese = "<html><body><p>日本語を読みます。</p></body></html>"
        let japaneseChapter = "<html xml:lang='ja-JP'><body><p>本文</p></body></html>"
        let chineseChapter = "<html lang='zh-CN'><body><p>日本語を引用。</p></body></html>"

        XCTAssertTrue(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "ja",
            xhtml: japanese
        ))
        XCTAssertFalse(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "zh-CN",
            xhtml: japanese
        ))
        XCTAssertTrue(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "zh",
            xhtml: japaneseChapter
        ))
        XCTAssertFalse(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "ja",
            xhtml: chineseChapter
        ))
    }

    func testEPUBFuriganaPolicyUsesKanaOnlyWhenLanguageIsUnspecified() {
        XCTAssertTrue(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "und",
            xhtml: "<html><body><p>静かな森を歩いている。</p></body></html>"
        ))
        XCTAssertFalse(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: nil,
            xhtml: "<html><body><p>这是一段没有日文假名的中文正文。</p></body></html>"
        ))
        XCTAssertFalse(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: nil,
            xhtml: "<html><body><p>中文正文中偶尔引用一个の字也不应改变整章语言。</p></body></html>"
        ))
    }

    func testEPUBFuriganaPolicyOverridesIncorrectEnglishMetadataForJapaneseChapter() {
        let mislabeledJapanese = """
        <html lang='en'><body><p>
        鮮やかな青みをたたえ、十月の風はすすきの穂をあちこちで揺らせ、
        細長い雲が凍りつくような青い天頂にぴたりとはりついていた。
        </p></body></html>
        """
        let mostlyChineseWithJapaneseQuote = """
        <html lang='zh'><body><p>
        这是中文章节的主要内容，用来介绍作品背景和人物关系。文中偶尔引用
        「静かな森を歩いている」作为日语例句，但不应因此给整章汉字添加日语读音。
        </p></body></html>
        """

        XCTAssertTrue(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "en",
            xhtml: mislabeledJapanese
        ))
        XCTAssertFalse(EPUBFuriganaPolicy.shouldAutomaticallyAnnotate(
            documentLanguage: "zh",
            xhtml: mostlyChineseWithJapaneseQuote
        ))
    }

    func testEPUBHandlerDoesNotInjectAutomaticFuriganaIntoChineseDocument() {
        let provider = StubJapaneseReadingProvider(segments: [
            .init(surface: "中文", reading: "ちゅうぶん")
        ])
        let xhtml = Data("<html><head></head><body><p>中文内容</p></body></html>".utf8)
        let chineseHandler = EPUBSchemeHandler(
            resources: [:],
            readingStyle: EPUBReadingStyle(showsFurigana: true),
            documentLanguage: "zh",
            japaneseReadingProvider: provider
        )
        let japaneseHandler = EPUBSchemeHandler(
            resources: [:],
            readingStyle: EPUBReadingStyle(showsFurigana: true),
            documentLanguage: "ja",
            japaneseReadingProvider: provider
        )

        let chineseHTML = String(data: chineseHandler.injectedXHTML(xhtml), encoding: .utf8)!
        let japaneseHTML = String(data: japaneseHandler.injectedXHTML(xhtml), encoding: .utf8)!
        XCTAssertFalse(chineseHTML.contains("const entries ="))
        XCTAssertTrue(japaneseHTML.contains("const entries ="))
        XCTAssertTrue(japaneseHTML.contains("ちゅうぶん"))
    }

    func testEPUBHandlerInjectsFuriganaWhenJapaneseBookIsMislabeledAsEnglish() {
        let provider = StubJapaneseReadingProvider(segments: [
            .init(surface: "青い", reading: "あおい")
        ])
        let xhtml = Data("""
        <html lang="en"><head></head><body><p>
        鮮やかな青みをたたえ、十月の風はすすきの穂をあちこちで揺らせ、
        細長い雲が凍りつくような青い天頂にぴたりとはりついていた。
        </p></body></html>
        """.utf8)
        let handler = EPUBSchemeHandler(
            resources: [:],
            readingStyle: EPUBReadingStyle(showsFurigana: true),
            documentLanguage: "en",
            japaneseReadingProvider: provider
        )

        let html = String(data: handler.injectedXHTML(xhtml), encoding: .utf8)!
        XCTAssertTrue(html.contains("const entries ="))
        XCTAssertTrue(html.contains("あおい"))
    }
}

private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func load() -> String { lock.withLock { value } }

    func save(_ value: String) -> Bool {
        lock.withLock { self.value = value }
        return true
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

private struct ProgressiveExplanationProvider: ReaderExplanationProviding {
    func explain(_ request: ReaderExplanationRequest) async throws -> ReaderExplanation {
        finalResult
    }

    func explanationStream(_ request: ReaderExplanationRequest) async throws -> AsyncThrowingStream<ReaderExplanation, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.init(
                    translation: "她继续", sentenceCore: "", grammarPoints: [], keyPhrases: []
                ))
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                continuation.yield(finalResult)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var finalResult: ReaderExplanation {
        .init(
            translation: "她继续了。", sentenceCore: "She continued.",
            grammarPoints: ["continued：一般过去时"], keyPhrases: []
        )
    }
}

private actor WordRequestRecorder {
    private(set) var request: WordExplanationRequest?
    func record(_ request: WordExplanationRequest) { self.request = request }
}

private struct RecordingVocabularyProvider: ReaderVocabularyProviding {
    let recorder: WordRequestRecorder

    func explainWord(_ request: WordExplanationRequest) async throws -> ReaderWordExplanation {
        await recorder.record(request)
        return .init(
            surface: request.selectedText,
            lemma: "continue",
            reading: nil,
            partOfSpeech: "verb",
            contextualMeaning: "继续走",
            briefMeaning: "继续",
            inflection: "continue 的过去式",
            collocations: []
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
