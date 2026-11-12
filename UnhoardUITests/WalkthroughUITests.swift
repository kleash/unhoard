import XCTest

/// One walkthrough on the simulator's library (add media with `simctl addmedia` first); screenshots go to the test
/// report and /tmp/unhoard-shots/design/. It never confirms a delete.
final class WalkthroughUITests: XCTestCase {
    let app = XCUIApplication()
    let shotDir = URL(fileURLWithPath: "/tmp/unhoard-shots/design")
    var step = 0

    func shot(_ name: String) {
        step += 1
        let label = String(format: "%02d-%@", step, name)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        try? png.write(to: shotDir.appendingPathComponent(label + ".png"))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = label
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// The previewed item's id (dates can repeat).
    var previewItem: String { app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'preview-'")).firstMatch.identifier }
    var cells: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "assetCell") }
    /// The tray count from the floating Delete button ("Delete 3 items, …"), 0 when it's hidden.
    var trayCount: Int {
        let b = el("deleteButton")
        guard b.exists, b.isHittable else { return 0 }
        return Int(b.label.split(separator: " ")[1]) ?? 0
    }

    let dark = "-UnhoardDark" // debug builds: the screenshots' colour scheme, without changing the shared simulator's

    func launch(_ arguments: String...) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
    }

    /// A short run for a screen recording (scripted with `simctl io recordVideo` around it): the live scan, then the swipe stack.
    func testRecordScanAndSwipe() throws {
        launch(dark, "-UnhoardFreshScan")
        if el("accessButton").waitForExistence(timeout: 3) { throw XCTSkip("Grant Photos access first (README).") }
        XCTAssertTrue(el("scanStatus").waitForExistence(timeout: 20), "a fresh scan shows the live hero")
        sleep(12)
        app.swipeUp()
        sleep(2)
        app.swipeDown()
        el("card-moments").tap()
        el("swipeButton").tap()
        let card = el("swipeCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        sleep(1)
        let middle = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: -110, dy: 20)), withVelocity: .slow, thenHoldForDuration: 1)
        sleep(1)
        card.swipeLeft()
        sleep(1)
        card.swipeRight()
        sleep(1)
        card.swipeLeft()
        sleep(1)
        app.buttons["Undo"].tap()
        sleep(1)
        app.buttons["Undo"].tap()
        sleep(1)
        app.buttons["Undo"].tap()
        sleep(1)
        el("swipeDone").tap()
    }

    func testWalkthrough() throws {
        launch(dark, "-UnhoardOnboarding")
        XCTAssertTrue(el("accessButton").waitForExistence(timeout: 5))
        sleep(1)
        shot("onboarding")

        // A fresh scan, for the live hero; the first swipe card opens mid-drag for its screenshot.
        launch(dark, "-UnhoardFreshScan", "-UnhoardDemoDrag")
        if el("accessButton").waitForExistence(timeout: 3) { app.terminate(); throw XCTSkip("Grant Photos access first (README).") }
        XCTAssertTrue(el("card-screenshots").waitForExistence(timeout: 10))
        if el("scanStatus").waitForExistence(timeout: 10) {
            sleep(5) // the mosaic fills
            shot("home-scanning")
        }
        waitForScan()
        sleep(1)
        shot("home-done")

        // The ring chart: a tap on the biggest cleanup slice (first, just clockwise from the top) opens its category.
        let ring = el("ringChart")
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        ring.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 18, dy: -112)).tap()
        XCTAssertTrue(el("swipeButton").waitForExistence(timeout: 5), "tapping a slice opens its category")
        back()

        // A category with nothing pre-selected, for gestures.
        el("card-moments").tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        // Start from nothing selected here (the tray persists between runs).
        if el("selectAllButton").label == "Select All" { el("selectAllButton").tap() }
        el("selectAllButton").tap()
        XCTAssertEqual(el("selectAllButton").label, "Select All")
        let before = trayCount
        cells.element(boundBy: 0).tap()
        XCTAssertEqual(trayCount, before + 1, "tap selects")
        cells.element(boundBy: 0).tap()
        XCTAssertEqual(trayCount, before, "tap again deselects")
        let dragged = cells.count >= 3
        if dragged {
            // Horizontal-first drag across the first row selects the range.
            let start = cells.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = cells.element(boundBy: 2).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(trayCount, before + 3, "drag selects the cells it passes")
            sleep(1)
            shot("category-grid")
            app.buttons["Selected"].tap()
            XCTAssertEqual(cells.count, 3, "the Selected filter shows only tray items")
            app.buttons["All"].tap()
        }
        cells.element(boundBy: 0).press(forDuration: 0.8)
        XCTAssertTrue(el("closePreview").waitForExistence(timeout: 5), "long-press previews")
        let firstTitle = previewItem
        app.swipeLeft()
        sleep(1)
        XCTAssertNotEqual(previewItem, firstTitle, "swiping the preview shows the next item")
        el("closePreview").tap()

        // The swipe stack.
        el("swipeButton").tap()
        let card = el("swipeCard")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        sleep(2)
        shot("swipe-stack-drag")
        let trayBefore = trayCount
        card.swipeLeft()
        sleep(1)
        XCTAssertEqual(trayCount, trayBefore + 1, "swipe left adds to the tray")
        app.buttons["Undo"].tap()
        sleep(1)
        XCTAssertEqual(trayCount, trayBefore, "undo takes it back out")
        el("swipeKeep").tap()
        sleep(1)
        XCTAssertEqual(trayCount, trayBefore, "keep doesn't add")
        app.buttons["Undo"].tap() // keeps are remembered: take it back so the next run's deck still has this item
        el("swipeDone").tap()

        // A pre-selecting category, then the commit sheet (closed without deleting).
        back()
        if dragged {
            // Long-press a card: delete just that category's selected items (closed without deleting).
            el("card-moments").press(forDuration: 1.2)
            let deleteCategory = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete' AND label ENDSWITH 'Selected'")).firstMatch
            XCTAssertTrue(deleteCategory.waitForExistence(timeout: 5), "a card's long-press offers deleting its selected items")
            deleteCategory.tap()
            XCTAssertTrue(el("commitDeleteButton").waitForExistence(timeout: 5))
            app.buttons["Close"].tap()
            sleep(1)
        }
        el("card-screenshots").tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        // Zoom, on a screenshot (always a photo): pinch in, then swiping down pans instead of closing.
        cells.element(boundBy: 0).press(forDuration: 0.8)
        XCTAssertTrue(el("closePreview").waitForExistence(timeout: 5))
        let zoomTitle = previewItem
        XCTAssertTrue(zoomTitle.hasPrefix("preview-"), "the preview names its item")
        app.pinch(withScale: 3, velocity: 2)
        sleep(1)
        XCTAssertTrue(el("closePreview").exists, "pinching doesn't close the preview")
        shot("preview-zoomed")
        app.swipeDown()
        sleep(1)
        XCTAssertTrue(el("closePreview").exists, "swiping down while zoomed pans instead of closing")
        if cells.count >= 2 {
            // Zoomed in, sideways swipes pan to the edge, then the next swipe goes to the next item; back, it fits again.
            for _ in 0..<4 where previewItem == zoomTitle { app.swipeLeft(); sleep(1) }
            XCTAssertNotEqual(previewItem, zoomTitle, "a swipe at the zoomed photo's edge goes to the next item")
            app.swipeRight()
            sleep(1)
            XCTAssertEqual(previewItem, zoomTitle)
        } else {
            app.doubleTap()
            sleep(1)
        }
        // Fit again: double-tap zooms in (swiping down pans), double-tap again fits (swiping down closes).
        app.doubleTap()
        sleep(1)
        app.swipeDown()
        sleep(1)
        XCTAssertTrue(el("closePreview").exists, "double-tap zooms in, and swiping down then pans")
        app.doubleTap()
        sleep(1)
        app.swipeDown()
        XCTAssertTrue(el("closePreview").waitForNonExistence(timeout: 5), "fit to screen, swiping down closes")
        // Nothing is pre-selected here: pick one for the commit sheet, and put it back after.
        let picked = trayCount == 0
        if picked { cells.element(boundBy: 0).tap() }
        XCTAssertTrue(el("deleteButton").waitForExistence(timeout: 5))
        el("deleteButton").tap()
        XCTAssertTrue(el("commitDeleteButton").waitForExistence(timeout: 5))
        sleep(1)
        shot("commit-sheet")
        app.buttons["Close"].tap()
        if picked { cells.element(boundBy: 0).tap() }
        back()

        // Sensitive: never bulk-selected; Hide is offered (never tapped here: it would ask to change the library).
        el("card-sensitive").tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "the passport page (simctl addmedia, see README) is found")
        let traySensitive = trayCount
        el("selectAllButton").tap() // disabled: isEnabled misreports for iOS 26 toolbar items, so check what it does
        XCTAssertEqual(trayCount, traySensitive, "Select All never picks sensitive items")
        shot("sensitive")
        cells.element(boundBy: 0).press(forDuration: 0.8)
        XCTAssertTrue(el("hideButton").waitForExistence(timeout: 5), "Hide in the preview")
        sleep(1)
        shot("sensitive-preview-hide")
        el("closePreview").tap()
        back()

        // Utility shots needs Vision's aesthetics request, which the simulator can't run.
        el("card-utility").tap()
        XCTAssertTrue(el("needsIPhone").waitForExistence(timeout: 5))
        back()

        // Home in light mode (before the stand-ins below, which label most sample pictures as utility shots).
        launch("-UnhoardLight")
        XCTAssertTrue(el("card-screenshots").waitForExistence(timeout: 10))
        waitForScan()
        sleep(1)
        shot("home-light")

        // Relaunch with debug stand-ins for what the simulator can't run (aesthetics, feature prints).
        launch(dark, "-UnhoardSimulatorStandIns")
        XCTAssertTrue(el("card-similar").waitForExistence(timeout: 10))
        waitForScan()
        el("card-similar").tap()
        XCTAssertTrue(el("similarGroupHeader").waitForExistence(timeout: 10), "groups have a header")
        XCTAssertTrue(cells.matching(NSPredicate(format: "label BEGINSWITH 'Best'")).firstMatch.exists, "each group's best is marked")
        sleep(1)
        shot("similar-grid")
        // Compare a group: pick the other shot as keeper, then switch back.
        el("compareButton").tap()
        let left = el("comparePane-0"), right = el("comparePane-1")
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        sleep(4) // full-size images load
        shot("similar-compare")
        XCTAssertTrue(left.label.hasSuffix("Keeper"))
        right.tap()
        sleep(1)
        XCTAssertTrue(right.label.hasSuffix("Keeper"), "tapping a shot makes it the keeper")
        left.tap()
        sleep(1)
        XCTAssertTrue(left.label.hasSuffix("Keeper"))
        el("compareDone").tap()
        back()

        // AI second opinion: Claude needs a key; the consent sheet shows what would be sent. Never sent here.
        el("card-utility").tap()
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        el("secondOpinionButton").tap()
        askClaude.tap()
        if el("apiKeyField").waitForExistence(timeout: 3) {
            el("apiKeyField").tap()
            el("apiKeyField").typeText("sk-ant-walkthrough-not-a-real-key")
            el("apiKeySave").tap()
            el("settingsDone").tap()
            el("secondOpinionButton").tap()
            askClaude.tap()
        }
        XCTAssertTrue(el("consentTitle").waitForExistence(timeout: 5))
        sleep(3) // previews load
        shot("ai-consent")
        el("consentCancel").tap()
        back()
        el("settingsButton").tap()
        XCTAssertTrue(el("settingsDone").waitForExistence(timeout: 5))
        sleep(1)
        shot("settings")
        if el("apiKeyRemove").waitForExistence(timeout: 3) { el("apiKeyRemove").tap() }
        el("settingsDone").tap()

        // The celebration with sample numbers (debug), then the history (sample entries when there are none yet).
        // A few frames, since the thumbnails and confetti are over in about 4 s; the best is kept as the screenshot.
        launch(dark, "-UnhoardCelebrationDemo")
        for frame in 0..<6 {
            usleep(600_000)
            shot("celebration-\(frame)")
        }
        XCTAssertTrue(el("celebrationSummary").waitForExistence(timeout: 15))
        el("celebrationHistory").tap()
        XCTAssertTrue(el("historyDone").waitForExistence(timeout: 5))
        sleep(1)
        shot("history")

    }

    var askClaude: XCUIElement { app.buttons.matching(NSPredicate(format: "identifier == 'askClaude' OR label BEGINSWITH 'Ask Claude'")).firstMatch }

    func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    /// Waits for the scan (and photo analysis) to finish, up to 5 minutes.
    func waitForScan() {
        sleep(2)
        let status = el("scanStatus")
        for _ in 0..<300 where status.exists { sleep(1) }
    }
}
