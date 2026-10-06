import XCTest

final class SwarmGateLaunchTests: XCTestCase {
    func testHomeScreenLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Swarm Gate"].waitForExistence(timeout: 10))
    }
}