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
}
