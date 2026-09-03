import XCTest

final class JieJuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReaderEmptyStateAppears() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["reader.openPDF"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["打开一份 PDF 开始阅读"].exists)
    }

    func testReviewEntryUsesGentleOptionalLanguage() {
        let app = XCUIApplication()
        app.launch()

        let reviewEntry = app.staticTexts["随手温习"]
        XCTAssertTrue(reviewEntry.waitForExistence(timeout: 5))
        reviewEntry.click()

        XCTAssertTrue(app.staticTexts["想看几张都可以，随时回到阅读"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["回到阅读"].exists)
        XCTAssertTrue(app.staticTexts["review.philosophy"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "待复习")).firstMatch.exists)
    }
}
