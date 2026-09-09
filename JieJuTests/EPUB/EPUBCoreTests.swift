import XCTest
import AppKit
import PDFKit
@testable import JieJu

final class EPUBCoreTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle(for: EPUBCoreTests.self).url(forResource: name, withExtension: "epub"))
    }

    func testParsesMinimalMetadata() throws {
        let doc = try EPUBCore.parse(url: try fixture("minimal"))
        XCTAssertEqual(doc.metadata.title, "Minimal Reader Test")
        XCTAssertEqual(doc.metadata.creator, "Jane Doe")
        XCTAssertEqual(doc.metadata.language, "en")
        XCTAssertEqual(doc.displayName, "Minimal Reader Test")
    }

    func testReadsSpineOrderAndSkipsNav() throws {
        let doc = try EPUBCore.parse(url: try fixture("minimal"))
        XCTAssertEqual(doc.chapters.count, 2)
        XCTAssertEqual(doc.chapters[0].id, "ch1")
        XCTAssertEqual(doc.chapters[1].id, "ch2")
    }

    func testExtractsParagraphBlocksWithInlineText() throws {
        let doc = try EPUBCore.parse(url: try fixture("minimal"))
        let blocks = doc.chapters[0].textBlocks
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], "Chapter One")
        XCTAssertEqual(blocks[1], "The first paragraph has emphasis and a bold word.")
        XCTAssertEqual(blocks[2], "Second paragraph, with a link.")
    }

    func testExposesManifestResourcesWithResolvedPackagePaths() throws {
        let doc = try EPUBCore.parse(url: try fixture("minimal"))
        let first = try XCTUnwrap(doc.chapters.first)

        XCTAssertEqual(first.resourcePath, "OEBPS/chapter1.xhtml")
        XCTAssertEqual(doc.resources[first.resourcePath]?.mediaType, "application/xhtml+xml")
        XCTAssertEqual(doc.resources[first.resourcePath]?.data, Data(first.rawXHTML.utf8))
        XCTAssertTrue(doc.resources.keys.allSatisfy { !$0.hasPrefix("/") && !$0.contains("../") })
    }

    func testDecodesEntitiesAndHandlesBreaksAndLists() throws {
        let doc = try EPUBCore.parse(url: try fixture("messy"))
        let blocks = doc.chapters[0].textBlocks
        XCTAssertTrue(blocks.contains { $0.contains("Dashes — and quotes “curly” and") })
        XCTAssertTrue(blocks.contains { $0.contains("Line one") && $0.contains("Line two") })
        XCTAssertTrue(blocks.contains("Item one"))
        XCTAssertTrue(blocks.contains("Item two"))
        XCTAssertTrue(blocks.contains { $0.contains("Nested & raw bold") })
    }

    func testRejectsNonZipData() {
        XCTAssertThrowsError(try EPUBCore.parse(data: Data("hello world".utf8))) { error in
            XCTAssertTrue(error is EPUBError)
        }
    }

    func testRejectsZipWithoutContainer() {
        XCTAssertThrowsError(try EPUBCore.parse(url: try fixture("nocontainer"))) { error in
            XCTAssertEqual(error as? EPUBError, .invalidContainer)
        }
    }

    func testRejectsEmptyData() {
        XCTAssertThrowsError(try EPUBCore.parse(data: Data()))
    }

    @MainActor
    func testReaderModelOpensEPUBAndClampsChapterNavigation() async throws {
        let suite = "JieJuTests.EPUBNavigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = ReaderViewModel(positionStore: ReadingPositionStore(defaults: defaults))
        model.open(try fixture("minimal"))

        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }

        guard case let .loaded(metadata) = model.documentState else {
            return XCTFail("EPUB did not finish loading")
        }
        XCTAssertEqual(metadata.kind, .epub)
        XCTAssertNotNil(model.epubDocument)
        XCTAssertNil(model.document)
        XCTAssertEqual(model.pageLabel, "第 1 / 2 章")

        model.showPreviousChapter()
        XCTAssertEqual(model.currentPageIndex, 0)
        model.updateSelection(.init(targetText: "Selected", precedingContext: nil, followingContext: nil, anchorRect: .zero))
        model.showNextChapter()
        XCTAssertNil(model.selection)
        for _ in 0...metadata.pageCount { model.showNextChapter() }
        XCTAssertEqual(model.currentPageIndex, metadata.pageCount - 1)
    }

    @MainActor
    func testReaderModelRestoresEPUBChapterAndPage() async throws {
        let suite = "JieJuTests.EPUBPosition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try fixture("minimal")
        let store = ReadingPositionStore(defaults: defaults)
        store.saveEPUB(chapterIndex: 1, pageIndex: 4, for: url)
        let model = ReaderViewModel(positionStore: store)

        model.open(url)
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }

        XCTAssertEqual(model.currentPageIndex, 1)
        XCTAssertEqual(model.currentEPUBPageIndex, 4)
        XCTAssertEqual(model.restoredEPUBPageIndex, 4)
        model.updateEPUBPage(2, pageCount: 3)
        let persisted = try XCTUnwrap(store.epubPosition(for: url))
        XCTAssertEqual(persisted.chapterIndex, 1)
        XCTAssertEqual(persisted.pageIndex, 2)
        XCTAssertEqual(persisted.chapterID, "ch2")
        XCTAssertEqual(persisted.chapterHref, "OEBPS/chapter2.xhtml")
        XCTAssertNil(persisted.textAnchor)
    }

    @MainActor
    func testReaderModelRestoresEPUBByStableChapterAndPersistsTextAnchor() async throws {
        let suite = "JieJuTests.EPUBStablePosition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try fixture("minimal")
        let store = ReadingPositionStore(defaults: defaults)
        let anchor = EPUBTextAnchor(textOffset: 17, textQuote: "paragraph", progression: 0.5)
        store.saveEPUB(.init(
            chapterIndex: 99,
            pageIndex: 7,
            chapterID: "outdated-id",
            chapterHref: "OEBPS/chapter2.xhtml",
            textAnchor: anchor
        ), for: url)
        let model = ReaderViewModel(positionStore: store)

        model.open(url)
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }

        XCTAssertEqual(model.currentPageIndex, 1)
        XCTAssertEqual(model.restoredEPUBTextAnchor, anchor)

        let updated = EPUBTextAnchor(textOffset: 31, textQuote: "visible text", progression: 0.7)
        model.updateEPUBPage(2, pageCount: 5, textAnchor: updated)
        let persisted = try XCTUnwrap(store.epubPosition(for: url))
        XCTAssertEqual(persisted.chapterID, "ch2")
        XCTAssertEqual(persisted.chapterHref, "OEBPS/chapter2.xhtml")
        XCTAssertEqual(persisted.pageIndex, 2)
        XCTAssertEqual(persisted.textAnchor, updated)
    }

    @MainActor
    func testReaderModelReturnsToSavedEPUBSourceInsteadOfCurrentReadingPosition() async throws {
        let suite = "JieJuTests.EPUBSourceNavigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = try fixture("minimal")
        let store = ReadingPositionStore(defaults: defaults)
        store.saveEPUB(chapterIndex: 0, pageIndex: 0, for: url)
        let anchor = EPUBTextAnchor(textOffset: 24, textQuote: "second chapter", progression: 0.6)
        let locator = DocumentLocator.epub(
            chapterHref: "OEBPS/chapter2.xhtml",
            textAnchor: anchor,
            displayPageIndex: 3
        )
        let model = ReaderViewModel(positionStore: store)

        model.openSource(.init(
            document: .init(id: url.path, fileName: url.lastPathComponent),
            locator: locator,
            legacyPageIndex: 0
        ))
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }

        XCTAssertEqual(model.currentPageIndex, 1)
        XCTAssertEqual(model.currentEPUBPageIndex, 3)
        XCTAssertEqual(model.restoredEPUBTextAnchor, anchor)
    }

    @MainActor
    func testReaderModelReturnsToSavedPDFPageInsteadOfCurrentReadingPosition() throws {
        let suite = "JieJuTests.PDFSourceNavigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jieju-source-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let document = PDFDocument()
        for index in 0..<3 {
            let image = NSImage(size: NSSize(width: 200, height: 300))
            image.lockFocus()
            NSString(string: "Page \(index + 1)").draw(at: NSPoint(x: 20, y: 20))
            image.unlockFocus()
            document.insert(try XCTUnwrap(PDFPage(image: image)), at: index)
        }
        XCTAssertTrue(document.write(to: url))
        let store = ReadingPositionStore(defaults: defaults)
        store.save(0, for: url)
        let model = ReaderViewModel(positionStore: store)

        model.openSource(.init(
            document: .init(id: url.path, fileName: url.lastPathComponent),
            locator: .pdf(pageIndex: 2),
            legacyPageIndex: 0
        ))

        XCTAssertEqual(model.currentPageIndex, 2)
        XCTAssertEqual(model.restoredPageIndex, 2)
    }

    @MainActor
    func testSavingExplanationPublishesSuccessStateAndPayload() async throws {
        let recorder = ReaderSavePayloadRecorder()
        let model = ReaderViewModel(saveHandler: { payload in
            await recorder.record(payload)
        })
        model.open(try fixture("minimal"))
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }
        let locator = DocumentLocator.epub(
            chapterHref: "OEBPS/chapter1.xhtml",
            textAnchor: .init(textOffset: 4, textQuote: "first paragraph", progression: 0.2),
            displayPageIndex: 1
        )
        model.updateSelection(.init(
            targetText: "The first paragraph.",
            precedingContext: nil,
            followingContext: nil,
            anchorRect: .zero,
            locator: locator
        ))
        model.requestExplanation()
        for _ in 0..<200 {
            if case .loaded = model.explanationState { break }
            await Task.yield()
        }

        model.saveExplanation()
        for _ in 0..<200 {
            if model.saveState == .saved { break }
            await Task.yield()
        }

        XCTAssertEqual(model.saveState, .saved)
        let savedPayload = await recorder.payload
        XCTAssertEqual(savedPayload?.selection.targetText, "The first paragraph.")
        XCTAssertEqual(savedPayload?.locator, locator)
    }

    @MainActor
    func testSavingVocabularyIncludesCurrentDocumentAndSentence() async throws {
        let recorder = ReaderVocabularyPayloadRecorder()
        let model = ReaderViewModel(vocabularySaveHandler: { payload in
            await recorder.record(payload)
        })
        let url = try fixture("minimal")
        model.open(url)
        for _ in 0..<200 {
            if case .loaded = model.documentState { break }
            await Task.yield()
        }
        let locator = DocumentLocator.epub(
            chapterHref: "OEBPS/chapter1.xhtml",
            textAnchor: .init(textOffset: 4, textQuote: "first paragraph", progression: 0.2),
            displayPageIndex: 1
        )
        model.updateSelection(.init(
            targetText: "The first paragraph has emphasis.",
            precedingContext: nil,
            followingContext: nil,
            anchorRect: .zero,
            locator: locator
        ))
        let candidate = ReaderVocabularyCandidate(
            surface: "emphasis",
            lemma: "emphasis",
            reading: nil,
            partOfSpeech: "noun",
            meaning: "强调"
        )

        try await model.saveVocabulary(candidate)

        let payload = await recorder.payload
        XCTAssertEqual(payload?.documentURL, url)
        XCTAssertEqual(payload?.sentence, "The first paragraph has emphasis.")
        XCTAssertEqual(payload?.candidate, candidate)
        XCTAssertEqual(payload?.sourceLanguage, "English")
        XCTAssertEqual(payload?.locator, locator)
    }
}

private actor ReaderSavePayloadRecorder {
    private(set) var payload: ReaderSavePayload?
    func record(_ payload: ReaderSavePayload) { self.payload = payload }
}

private actor ReaderVocabularyPayloadRecorder {
    private(set) var payload: ReaderVocabularySavePayload?
    func record(_ payload: ReaderVocabularySavePayload) { self.payload = payload }
}
