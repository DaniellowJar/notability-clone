import XCTest

/// Reproduces the reported defect end to end: create notebook → land on its
/// Pages screen, open a page → its canvas, tap New Page → creates and opens a
/// fresh canvas, both pages listed and deletable. Runs against an in-memory
/// store on the iPad simulator.
///
/// iOS 26.2 simulator probe results (2025-09):
/// - `navigationBars["Untitled"]` is NOT exposed for inline nav titles.
/// - `PKCanvasView.accessibilityIdentifier = "canvas"` is NOT surfaced.
/// - The only reliable pushed-screen signal is the back button whose label
///   matches the *previous* screen's nav title (e.g. "Notability", "TestNB").
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

        // The create sheet must dismiss and the Pages screen must push — not
        // straight into a blank canvas with nothing to tap.
        XCTAssertFalse(app.textFields["notebookTitle"].waitForExistence(timeout: 5),
                       "create sheet should dismiss after tapping Create")
        XCTAssertFalse(app.alerts.firstMatch.exists, "creating should not raise an error alert")
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8),
                      "creating a notebook should open its Pages screen with a New Page button")

        // 2. The auto-created page is listed.
        XCTAssertTrue(app.staticTexts["Untitled"].waitForExistence(timeout: 8),
                      "auto-created page must appear in the Pages list")

        // 3. Open it → canvas; back returns to Pages.
        app.staticTexts["Untitled"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "tapping a page should push its canvas")
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 5),
                      "backing out of a canvas should return to Pages")

        // 4. One-tap New Page → creates and opens its canvas directly.
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "tapping New Page should create a page and open its canvas")

        // 5. Back: both pages are listed.
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Untitled"].exists)

        // 6. Page persists after leaving the notebook and re-entering.
        app.navigationBars.firstMatch.buttons["Notability"].tap()
        XCTAssertTrue(app.staticTexts["TestNB"].waitForExistence(timeout: 8),
                      "notebook should be visible in the grid")
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Page 2"].waitForExistence(timeout: 8),
                      "page must persist when re-entering the notebook")

        // 7. Swipe-to-delete the created page.
        app.staticTexts["Page 2"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["Page 2"].waitForExistence(timeout: 5))
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
}
