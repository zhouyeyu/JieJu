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
}
