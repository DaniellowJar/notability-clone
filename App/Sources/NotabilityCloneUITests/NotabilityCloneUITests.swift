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
        XCTAssertTrue(deletePage(app, titled: "Page 1"), "swipe should reveal and tap Delete")
        XCTAssertFalse(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
    }

    /// Drags a line across the middle of the canvas to produce one PencilKit
    /// stroke (the canvas fills the screen).
    private func drawStroke(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    func testCreateTextBlockViaMarqueeAndPersist() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Notebook → New Page → canvas.
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("Blocks")
        app.buttons["createNotebook"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8))
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Blocks"))

        // 1. Text tool → drag a marquee → a text block is created and focused.
        app.buttons["toolText"].tap()
        let marqueeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        let marqueeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45))
        marqueeStart.press(forDuration: 0.05, thenDragTo: marqueeEnd)
        XCTAssertTrue(app.waitForDebug(label: "blocks=1", timeout: 5),
                      "marquee should create a text block")

        // 2. Type into the focused text block.
        if app.keyboards.firstMatch.waitForExistence(timeout: 6) {
            app.typeText("Hello block")
        } else {
            app.typeText("Hello block")
        }

        // 3. Done → block stays, editable as static text.
        app.buttons["toolDone"].tap()
        XCTAssertTrue(app.waitForDebug(label: "blocks=1", timeout: 5))

        // 4. Leave and re-enter: the block persists.
        app.navigationBars.firstMatch.buttons["Blocks"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
        app.staticTexts["Page 1"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Blocks"))
        XCTAssertTrue(app.waitForDebug(label: "blocks=1", timeout: 5),
                      "text block must persist across re-entry")
    }

    func testFingerPaintingToggleEnablesTouchDrawing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // 1. Open Settings from the root toolbar and turn finger drawing on.
        // (Each launch resets preferences, so the toggle starts OFF.)
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["fingerPaintingToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8),
                      "finger toggle should appear in Settings")
        // Tap the switch control itself (row trailing edge) — tapping the row
        // center can miss the control on iPad Form layouts.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(3)
        while (toggle.value as? String) != "1", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(toggle.value as? String, "1", "toggle must switch on")

        // Dismiss Settings: tap Done (global lookup — firstMatch nav bar can be
        // the root's), falling back to swipe-down, then wait until it's gone.
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 5) {
            done.tap()
        } else {
            app.sheets.firstMatch.swipeDown()
        }
        let goneBy = Date().addingTimeInterval(5)
        while toggle.exists, Date() < goneBy {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertFalse(toggle.exists, "Settings sheet should dismiss")

        // 2. Notebook → New Page → canvas.
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("Fingers")
        app.buttons["createNotebook"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8))
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Fingers"))

        // 3. A finger drag must register a stroke (touch drawing allowed).
        drawStroke(in: app)
        XCTAssertTrue(app.waitForDebug(label: "strokes=1", timeout: 5),
                      "finger drag must draw when the toggle is on")
    }

    func testPageHeaderAndPinchZoom() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Notebook → New Page → canvas.
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("Zoom")
        app.buttons["createNotebook"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8))
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Zoom"))

        // 1. The creation-date header is pinned at the top of the page.
        XCTAssertTrue(app.staticTexts["pageHeader"].waitForExistence(timeout: 5),
                      "page header should show the creation date")

        // 2. Pinch in → the debug label must report a zoom above 1.00.
        // (Pinch is centered on the debug label; both fingers land inside the
        // viewport so the canvas zoom recognizer picks it up.)
        app.staticTexts["canvasDebug"].pinch(withScale: 2.5, velocity: 1.0)
        XCTAssertTrue(app.waitForZoomChanged(timeout: 10),
                      "pinch must change the canvas zoom")
    }

    func testLetterModeZoomToFit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Notebook → New Page → canvas.
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("Letter")
        app.buttons["createNotebook"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8))
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Letter"))

        // Letter tool → marquee an area → canvas zooms to fit it across
        // the screen (debug zoom leaves 1.00). Commit math is unit-tested;
        // here we verify the marquee→zoom wiring end to end.
        app.buttons["toolLetter"].tap()
        let marqueeStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35))
        let marqueeEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45))
        marqueeStart.press(forDuration: 0.05, thenDragTo: marqueeEnd)
        XCTAssertTrue(app.waitForZoomChanged(timeout: 10),
                      "letter marquee must zoom to fit the area")
    }

    func testPageTexturePersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore"]
        app.launch()

        // Notebook → New Page → canvas (fresh pages start plain).
        XCTAssertTrue(presentSheet(in: app, byTapping: "addNotebook",
                                   waitingFor: app.textFields["notebookTitle"]),
                      "notebook title field should appear")
        let notebookField = app.textFields["notebookTitle"]
        notebookField.tap()
        notebookField.typeText("Texture")
        app.buttons["createNotebook"].tap()
        XCTAssertTrue(app.buttons["addPage"].waitForExistence(timeout: 8))
        app.buttons["addPage"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Texture"))
        XCTAssertTrue(app.waitForDebug(label: "texture=plain", timeout: 5))

        // Switch the page background to dots.
        app.buttons["toolTexture"].tap()
        let dots = app.buttons["texture-dots"]
        XCTAssertTrue(dots.waitForExistence(timeout: 5), "texture picker should list dots")
        dots.tap()
        XCTAssertTrue(app.waitForDebug(label: "texture=dots", timeout: 5),
                      "texture switch must apply to the page")

        // Leave and re-enter: the texture persists per page.
        app.navigationBars.firstMatch.buttons["Texture"].tap()
        XCTAssertTrue(app.staticTexts["Page 1"].waitForExistence(timeout: 5))
        app.staticTexts["Page 1"].tap()
        XCTAssertTrue(app.waitForCanvas(backButtonLabel: "Texture"))
        XCTAssertTrue(app.waitForDebug(label: "texture=dots", timeout: 5),
                      "page texture must persist across re-entry")
    }

    /// Reveals the row's Delete action and taps it. A short right-to-left drag
    /// is used on purpose: a full-row swipe triggers iOS's full-swipe delete,
    /// which removes the row without a Delete button ever appearing (and this
    /// List holds only one page, so a full swipe is easy to trigger). Either
    /// outcome is a successful deletion.
    private func deletePage(_ app: XCUIApplication, titled title: String) -> Bool {
        for _ in 0..<3 {
            let cell = app.cells.containing(.staticText, identifier: title).firstMatch
            guard cell.exists else { return true } // already gone (full-swipe delete)
            let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
            let delete = app.buttons["Delete"].firstMatch
            if delete.waitForExistence(timeout: 3) {
                delete.tap()
                return true
            }
            if !cell.waitForExistence(timeout: 1) { return true } // full-swipe delete
        }
        print("DELETE-missing title=\(title)")
        print(app.debugDescription)
        return false
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

    /// Polls the DEBUG canvas label until the zoom differs from 1.00 — how
    /// pinch zoom is verified from XCUITest (pixel scale isn't readable).
    func waitForZoomChanged(timeout: TimeInterval = 10) -> Bool {
        let debug = staticTexts["canvasDebug"]
        guard debug.waitForExistence(timeout: 3) else {
            print("DEBUG-label-missing")
            print(debugDescription)
            return false
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !debug.label.contains("zoom=1.00") { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        print("DEBUG-zoom-never-changed label=\(debug.label)")
        return false
    }
}
