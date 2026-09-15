import XCTest

/// Reproduces the reported defects end to end:
/// 1. Creating a notebook opens its empty Pages screen — NO auto-created page.
/// 2. One-tap New Page → "Page 1" → a fresh canvas, and strokes persist after
///    leaving the canvas and re-entering (previously they were deleted).
///
/// Runs against an in-memory store on the iPad simulator.
///
/// iOS 26.2 simulator probe results (2025-09):
/// - `navigationBars["Untitled"]` is NOT exposed for inline nav titles.
/// - `PKCanvasView.accessibilityIdentifier = "canvas"` is NOT surfaced.
/// - The only reliable pushed-screen signal is the back button whose label
///   matches the *previous* screen's nav title (e.g. "Notability", "TestNB").
/// - Stroke persistence is asserted via the DEBUG "canvasDebug" label
///   (`strokes=N saved=N`) since canvas pixels are not readable from XCUITest.
final class NotabilityCloneUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Cold-booted simulators are slow to present their first sheet; tap once,
    /// then re-tap before giving up, and dump the hierarchy if both fail.
    func presentSheet(in app: XCUIApplication, byTapping id: String,
                      waitingFor element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        for attempt in 1...2 {
            let button = app.buttons[id]
            if !button.exists {
                print("PROBE1 attempt=\(attempt) button=\(id) missing")
            } else {
                button.tap()
            }
            if element.waitForExistence(timeout: attempt == 1 ? 6 : timeout) { return true }
            print("PROBE1 attempt=\(attempt) sheet-not-present")
            if let content = element.value as? String { print("PROBE1 value=\(content)") }
        }
        print("HIER-BEGIN")
        print(app.debugDescription)
        print("HIER-END")
        return false
    }

    func testNotebookAndRecordFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // 1. Create a notebook from the root grid.
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("TestNB")
        app.buttons["createNotebook"].tap()

        // The create sheet must dismiss and the Pages screen must push — with
        // NO auto-created page (the user makes pages their own way).
        XCTAssertFalse(app.textFields["notebookTitle"].waitForExistence(timeout: 5),
                       "create sheet should dismiss after tapping Create")
        XCTAssertFalse(app.alerts.firstMatch.exists, "creating should not raise an error alert")
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8),
                      "creating a notebook should open its Pages screen with a New Page button")
        XCTAssertFalse(app.staticTexts["Untitled"].exists,
                       "no auto-created page should exist — only what the user adds")

        // 2. One-tap New Page → creates "Page 1" and opens its canvas directly.
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "tapping New Page should create a page and open its canvas")
        XCTAssertTrue(app.waitForDebug(label: "strokes=0", timeout: 5),
                      "fresh canvas starts empty")

        // 3. Draw a real stroke; the debug label must report it saved.
        drawStroke(in: app)
        XCTAssertTrue(app.waitForDebug(label: "strokes=1", timeout: 5),
                      "drawing must register a stroke")
        XCTAssertTrue(app.waitForDebug(label: "saved=1", timeout: 5),
                      "drawn stroke must be persisted to the store")

        // 4. Back: the created page is listed as "Page 1".
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5),
                      "the created page must be listed in Pages")

        // 5. Re-enter the page → the stroke must still be there (the fix for
        //    strokes being deleted on back-navigation).
        app.staticTexts["Page 1"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "tapping the page should push its canvas")
        XCTAssertTrue(app.waitForDebug(label: "strokes=1", timeout: 5),
                      "persisted stroke must load when re-entering the canvas")

        // 6. Page persists after leaving the notebook and re-entering.
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        app.navigationBars.firstMatch.buttons["Notability"].tap()
        XCTAssertTrue(app.staticTexts["TestNB"].waitForExistence(timeout: 8),
                      "notebook should be visible in the grid")
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 8),
                      "page must persist when re-entering the notebook")

        // 7. Swipe-to-delete the created page.
        app.staticTexts["Page 1"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
    }

    /// Drags a line across the middle of the canvas to produce one PencilKit
    /// stroke (the canvas fills the screen).
    private func drawStroke(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
}

private extension XCUIApplication {
    /// Waits for a pushed canvas by looking for a back button whose label
    /// matches `backButtonLabel` (the previous screen's nav title). This is
    /// the only reliable signal on iOS 26.2 where inline nav titles and
    /// PKCanvasView accessibility identifiers are not exposed to XCUITest.
    func waitForCanvas(backButtonLabel: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if navigationBars.firstMatch.buttons[backButtonLabel].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        return false
    }

    /// Polls the DEBUG canvas label ("strokes=N saved=N") until it contains the
    /// given substring — how stroke persistence is verified from XCUITest.
    func waitForDebug(label substring: String, timeout: TimeInterval = 8) -> Bool {
        let debug = staticTexts["canvasDebug"]
        guard debug.waitForExistence(timeout: 3) else {
            print("DEBUG-label-missing")
            print(debugDescription)
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if debug.label.contains(substring) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        print("DEBUG-never-contained=\(substring) label=\(debug.label)")
        return false
    }
}
