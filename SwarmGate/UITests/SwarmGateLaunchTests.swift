import XCTest

final class SwarmGateLaunchTests: XCTestCase {
    func testMenuRunSummaryJourney() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Swarm Gate"].waitForExistence(timeout: 10))
        app.buttons["settings.button"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        app.buttons["settings.done"].tap()
        app.buttons["mode.quick"].tap()
        XCTAssertTrue(app.staticTexts["hud.wave"].waitForExistence(timeout: 10))
        app.buttons["control.surrender"].tap()
        XCTAssertTrue(app.staticTexts["summary.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["summary.waves"].exists)
        app.buttons["summary.dismiss"].tap()
        XCTAssertTrue(app.buttons["mode.quick"].waitForExistence(timeout: 10))
    }
}
