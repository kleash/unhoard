import XCTest

/// App Store screenshots: run on a simulator loaded with stock media only (see README), never a real library.
///   xcodebuild test -scheme UnhoardUI -only-testing:UnhoardUITests/StoreScreenshotsUITests -destination 'id=<demo sim>'
/// Saves 1320×2868 PNGs (on a 6.9" simulator) to /tmp/unhoard-store/.
final class StoreScreenshotsUITests: XCTestCase {
    let app = XCUIApplication()
    let dir = URL(fileURLWithPath: "/tmp/unhoard-store")

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func save(_ name: String) {
        sleep(2) // images and animations settle
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: dir.appending(path: "\(name).png"))
    }

    func testStoreScreenshots() throws {
        app.launchArguments = ["-UnhoardDark", "-UnhoardSimulatorStandIns"]
        app.launch()
        XCTAssertTrue(el("card-screenshots").waitForExistence(timeout: 20))
        for _ in 0..<300 where el("scanStatus").exists { sleep(1) } // a finished scan, so every category is filled

        // 4. Home, scrolled so the Blurry and Large Videos cards show their counts.
        // An exact, slow drag (no fling): "On this day" just below the bar, the six category cards in view.
        let onThisDay = el("onThisDay")
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        let lift = onThisDay.frame.minY - app.navigationBars.firstMatch.frame.maxY - 12
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -lift)), withVelocity: 150, thenHoldForDuration: 0.6)
        save("04-home")
        app.swipeDown(velocity: .fast)

        // 1. Screenshots grid, all selected ("in one go"), then deselected again.
        el("card-screenshots").tap()
        XCTAssertTrue(el("selectAllButton").waitForExistence(timeout: 10))
        el("selectAllButton").tap()
        save("01-screenshots")
        el("selectAllButton").tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 2. Swipe mode on photos (Utility Shots), after one left swipe so the counter shows real bytes (undone after).
        el("card-utility").tap()
        XCTAssertTrue(el("swipeButton").waitForExistence(timeout: 10))
        el("swipeButton").tap()
        let card = el("swipeCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.swipeLeft()
        save("02-swipe")
        app.buttons["Undo"].tap()
        el("swipeDone").tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 3. Similar Shots: compare.
        el("card-similar").tap()
        XCTAssertTrue(el("compareButton").waitForExistence(timeout: 10))
        el("compareButton").tap()
        XCTAssertTrue(el("compareDone").waitForExistence(timeout: 10))
        save("03-compare")
        el("compareDone").tap()

        // 5. The delete tray (Similar Shots pre-selects its extra shots).
        XCTAssertTrue(el("deleteButton").waitForExistence(timeout: 10))
        el("deleteButton").tap()
        XCTAssertTrue(el("commitDeleteButton").waitForExistence(timeout: 10))
        save("05-tray")
    }
}
