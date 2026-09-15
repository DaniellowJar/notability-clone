import XCTest

/// Reproduces the reported defect end to end: create notebook → land on a
/// canvas, create a record → land on its canvas, both visible in the list,
/// and deletable. Runs against an in-memory store on the iPad simulator.
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

    func testNotebookAndRecordFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // 1. Create a notebook from the root grid.
        app.buttons["addNotebook"].tap()
        let notebookField = app.textFields["notebookTitle"]
        XCTAssertTrue(notebookField.waitForExistence(timeout: 5), "notebook title field should appear")
        notebookField.tap()
        notebookField.typeText("TestNB")
        app.buttons["createNotebook"].tap()

        // The create sheet must dismiss and the canvas must push.
        XCTAssertFalse(app.textFields["notebookTitle"].waitForExistence(timeout: 5),
                       "create sheet should dismiss after tapping Create")
        XCTAssertFalse(app.alerts.firstMatch.exists, "creating should not raise an error alert")
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Notability"),
                      "creating a notebook should auto-open a canvas")

        // 2. Back to the grid; the notebook persists.
        app.navigationBars.firstMatch.buttons["Notability"].tap()
        XCTAssertTrue(app.staticTexts["TestNB"].waitForExistence(timeout: 5),
                      "notebook should be visible in the grid")

        // 3. Open it: the auto-created record must be in the list.
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Untitled"].waitForExistence(timeout: 5),
                      "auto-created record must appear in the records list")

        // 4. Create a named record → straight to its canvas.
        app.buttons["addRecord"].tap()
        let recordField = app.textFields["recordTitle"]
        XCTAssertTrue(recordField.waitForExistence(timeout: 5), "record title field should appear")
        recordField.tap()
        recordField.typeText("TestRec")
        app.buttons["createRecord"].tap()
        XCTAssertFalse(app.textFields["recordTitle"].waitForExistence(timeout: 5),
                       "create-record sheet should dismiss after tapping Create")
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "creating a record should push its canvas")

        // 5. Back: both records are listed.
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["TestRec"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Untitled"].exists)

        // 6. Record persists after leaving the notebook and re-entering.
        app.navigationBars.firstMatch.buttons["Notability"].tap()
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["TestRec"].waitForExistence(timeout: 5),
                      "record must persist when re-entering the notebook")

        // 7. Swipe-to-delete the named record.
        app.staticTexts["TestRec"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["TestRec"].waitForExistence(timeout: 5))
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
