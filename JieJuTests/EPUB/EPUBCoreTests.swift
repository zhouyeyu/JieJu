import XCTest
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
        XCTAssertEqual(store.epubPosition(for: url), EPUBReadingPosition(chapterIndex: 1, pageIndex: 2))
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
        model.updateSelection(.init(
            targetText: "The first paragraph.",
            precedingContext: nil,
            followingContext: nil,
            anchorRect: .zero
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
    }
}

private actor ReaderSavePayloadRecorder {
    private(set) var payload: ReaderSavePayload?
    func record(_ payload: ReaderSavePayload) { self.payload = payload }
}
