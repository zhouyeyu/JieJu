import XCTest

final class JieJuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeScreenAppears() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["JieJu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["从真实阅读中学习语言"].exists)
    }
}

