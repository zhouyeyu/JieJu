import XCTest
@testable import JieJu

final class ReaderTextProcessorTests: XCTestCase {
    func testCleanCollapsesWhitespaceAndJoinsPDFHyphenation() {
        let input = "Language learn-\ning  works\n  through reading."
        XCTAssertEqual(
            ReaderTextProcessor.clean(input),
            "Language learning works through reading."
        )
    }

    func testCleanPreservesSemanticHyphen() {
        XCTAssertEqual(ReaderTextProcessor.clean("A well-known author"), "A well-known author")
    }

    func testContextReturnsNearestSentences() {
        let source = "The first sentence. This is the selected phrase in context! The final sentence?"
        let result = ReaderTextProcessor.context(for: "selected phrase", in: source)
        XCTAssertEqual(result.current, "This is the selected phrase in context!")
        XCTAssertEqual(result.preceding, "The first sentence.")
        XCTAssertEqual(result.following, "The final sentence?")
    }

    func testContextReturnsNilWhenSelectionIsMissing() {
        let result = ReaderTextProcessor.context(for: "missing", in: "A different sentence.")
        XCTAssertNil(result.current)
        XCTAssertNil(result.preceding)
        XCTAssertNil(result.following)
    }

    func testContextHandlesChinesePunctuation() {
        let result = ReaderTextProcessor.context(for: "目标", in: "前一句。这里是目标内容！后一句？")
        XCTAssertEqual(result.current, "这里是目标内容！")
        XCTAssertEqual(result.preceding, "前一句。")
        XCTAssertEqual(result.following, "后一句？")
    }

    func testPreparedSelectionDropsAccidentalTrailingSentenceFragment() {
        XCTAssertEqual(
            ReaderTextProcessor.preparedSelection("僕は十八で、大学に入ったばかりだった。東京の"),
            "僕は十八で、大学に入ったばかりだった。"
        )
        XCTAssertEqual(ReaderTextProcessor.preparedSelection("東京の"), "東京の")
        XCTAssertEqual(ReaderTextProcessor.preparedSelection("第一句。第二句。"), "第一句。第二句。")
    }
}
