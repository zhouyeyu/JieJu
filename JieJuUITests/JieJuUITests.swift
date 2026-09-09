import XCTest

final class JieJuUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReaderEmptyStateAppears() {
        let app = launchApp()

        XCTAssertTrue(app.buttons["reader.openDocument"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["回到阅读"].exists)
        XCTAssertTrue(app.staticTexts["从上次停下的地方继续，或者打开一本新书。"].exists)
    }

    func testReviewEntryUsesGentleOptionalLanguage() {
        let app = launchApp()

        let reviewEntry = app.descendants(matching: .any)["navigation.review"]
        XCTAssertTrue(reviewEntry.waitForExistence(timeout: 5))
        reviewEntry.click()

        XCTAssertTrue(app.staticTexts["想看几张都可以，随时回到阅读"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["回到阅读"].exists)
        XCTAssertTrue(app.staticTexts["review.philosophy"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "待复习")).firstMatch.exists)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        return app
    }
}
