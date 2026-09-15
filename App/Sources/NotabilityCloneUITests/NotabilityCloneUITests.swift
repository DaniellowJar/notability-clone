import XCTest

/// Reproduces the reported defect end to end: create notebook → land on a
/// canvas, create a record → land on its canvas, both visible in the list,
/// and deletable. Runs against an in-memory store on the iPad simulator.
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

        // 2. Land straight on the auto-created canvas.
        XCTAssertTrue(app.waitForCanvas(title: "Untitled"),
                      "creating a notebook should auto-open a canvas")
        app.navigationBars["Untitled"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["TestNB"].waitForExistence(timeout: 5),
                      "notebook should be visible in the grid")

        // 3. Open it: the auto-created record must be in the list.
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["Untitled"].waitForExistence(timeout: 5),
                      "auto-created record must appear in the records list")

        // 5. Create a named record → straight to its canvas.
        app.buttons["addRecord"].tap()
        let recordField = app.textFields["recordTitle"]
        XCTAssertTrue(recordField.waitForExistence(timeout: 5), "record title field should appear")
        recordField.tap()
        recordField.typeText("TestRec")
        app.buttons["createRecord"].tap()
        XCTAssertTrue(app.waitForCanvas(title: "TestRec"),
                      "creating a record should push its canvas")

        // 6. Back: both records are listed.
        app.navigationBars["TestRec"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["TestRec"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Untitled"].exists)

        // 7. Record persists after leaving the notebook and re-entering.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["TestNB"].tap()
        XCTAssertTrue(app.staticTexts["TestRec"].waitForExistence(timeout: 5),
                      "record must persist when re-entering the notebook")

        // 8. Swipe-to-delete the named record.
        app.staticTexts["TestRec"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertFalse(app.staticTexts["TestRec"].waitForExistence(timeout: 5))
    }
}

private extension XCUIApplication {
    /// The canvas is a UIKit view exposed to accessibility as "canvas"; its
    /// navigation bar carries the record title. Accept either so the check
    /// survives how UIKit/SwiftUI chooses to expose the view.
    func waitForCanvas(title: String, timeout: TimeInterval = 8) -> Bool {
        if navigationBars[title].waitForExistence(timeout: timeout) { return true }
        return descendants(matching: .any).matching(identifier: "canvas")
            .firstMatch.waitForExistence(timeout: timeout)
    }
}