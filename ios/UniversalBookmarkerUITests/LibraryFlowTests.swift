import XCTest

final class LibraryFlowTests: XCTestCase {
    @MainActor
    func testLibraryCollectionsAndSearchNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting-demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Collections"].tap()
        XCTAssertTrue(app.navigationBars["Collections"].exists)
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].exists)
    }
}
