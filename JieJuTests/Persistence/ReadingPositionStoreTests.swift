import XCTest
@testable import JieJu

final class ReadingPositionStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ReadingPositionStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.ReadingPositionStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ReadingPositionStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testNoSavedPositionReturnsNil() {
        XCTAssertNil(store.position(for: URL(fileURLWithPath: "/tmp/never-opened.pdf")))
    }

    func testSaveAndRestore() {
        let url = URL(fileURLWithPath: "/tmp/a.pdf")
        store.save(7, for: url)
        XCTAssertEqual(store.position(for: url), 7)
    }

    func testSavesFirstPage() {
        let url = URL(fileURLWithPath: "/tmp/b.pdf")
        store.save(0, for: url)
        XCTAssertEqual(store.position(for: url), 0)
    }

    func testIsolatesDocuments() {
        let a = URL(fileURLWithPath: "/tmp/a.pdf")
        let b = URL(fileURLWithPath: "/tmp/b.pdf")
        store.save(3, for: a)
        store.save(9, for: b)
        XCTAssertEqual(store.position(for: a), 3)
        XCTAssertEqual(store.position(for: b), 9)
    }

    func testSameFileViaDifferentSpellingSharesKey() {
        let canonical = URL(fileURLWithPath: "/tmp/shared.pdf")
        let spelled = URL(fileURLWithPath: "/tmp/./shared.pdf")
        store.save(4, for: spelled)
        XCTAssertEqual(store.position(for: canonical), 4)
    }

    func testClearRemovesPosition() {
        let url = URL(fileURLWithPath: "/tmp/c.pdf")
        store.save(5, for: url)
        store.clear(for: url)
        XCTAssertNil(store.position(for: url))
    }

    func testSaveAndRestoreEPUBChapterAndPage() {
        let url = URL(fileURLWithPath: "/tmp/book.epub")

        store.saveEPUB(chapterIndex: 3, pageIndex: 12, for: url)

        XCTAssertEqual(store.epubPosition(for: url), EPUBReadingPosition(chapterIndex: 3, pageIndex: 12))
    }

    func testSaveAndRestoreStableEPUBTextAnchor() {
        let url = URL(fileURLWithPath: "/tmp/anchored.epub")
        let anchor = EPUBTextAnchor(
            textOffset: 428,
            textQuote: "The sentence visible at the top of the page.",
            progression: 0.42
        )
        let position = EPUBReadingPosition(
            chapterIndex: 3,
            pageIndex: 12,
            chapterID: "chapter-four",
            chapterHref: "OEBPS/chapter4.xhtml",
            textAnchor: anchor
        )

        store.saveEPUB(position, for: url)

        XCTAssertEqual(store.epubPosition(for: url), position)
    }

    func testDecodesLegacyEPUBPositionWithoutStableAnchor() throws {
        let legacy = Data(#"{"chapterIndex":2,"pageIndex":8}"#.utf8)
        let position = try JSONDecoder().decode(EPUBReadingPosition.self, from: legacy)

        XCTAssertEqual(position, EPUBReadingPosition(chapterIndex: 2, pageIndex: 8))
        XCTAssertNil(position.chapterHref)
        XCTAssertNil(position.textAnchor)
    }

    func testClearRemovesEPUBPosition() {
        let url = URL(fileURLWithPath: "/tmp/book.epub")
        store.saveEPUB(chapterIndex: 2, pageIndex: 8, for: url)

        store.clear(for: url)

        XCTAssertNil(store.epubPosition(for: url))
    }
}
