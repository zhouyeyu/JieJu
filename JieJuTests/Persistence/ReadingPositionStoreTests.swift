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
}
