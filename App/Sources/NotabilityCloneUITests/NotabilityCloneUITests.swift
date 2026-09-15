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

        // The create sheet must dismiss and the record list must push — not
        // straight into a blank canvas with nothing to tap.
        XCTAssertFalse(app.textFields["notebookTitle"].waitForExistence(timeout: 5),
                       "create sheet should dismiss after tapping Create")
        XCTAssertFalse(app.alerts.firstMatch.exists, "creating should not raise an error alert")
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 8),
                      "creating a notebook should open its record list")

        // 2. The auto-created record is listed.
        XCTAssertTrue(app.staticTexts["Untitled"].waitForExistence(timeout: 8),
                      "auto-created record must appear in the records list")

        // 3. Open it → canvas; back returns to the list.
        app.staticTexts["Untitled"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "TestNB"),
                      "tapping a record should push its canvas")
        app.navigationBars.firstMatch.buttons["TestNB"].tap()
        XCTAssertTrue(app.buttons["addRecord"].waitForExistence(timeout: 5),
                      "backing out of a canvas should return to the record list")

        // 4. Create a named record → straight to its canvas.
        app.buttons["addRecord"].tap()
        let recordField = app.textFields["recordTitle"]
        XCTAssertTrue(recordField.waitForExistence(timeout: 8), "record title field should appear")
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
        XCTAssertTrue(app.staticTexts["TestNB"].waitForExistence(timeout: 8),
                      "notebook should be visible in the grid")
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["TestRec"].waitForExistence(timeout: 8),
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
