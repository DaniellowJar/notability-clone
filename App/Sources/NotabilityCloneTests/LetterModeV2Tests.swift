import NotabilityCore
import XCTest
@testable import NotabilityClone

final class LetterModeV2Tests: XCTestCase {
    private var store: NotabilityStore!
    private var recordID: UUID!

    override func setUpWithError() throws {
        store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        recordID = try store.createRecord(in: nb.id, title: "r").id
    }

    private func stroke(x0: Double, x1: Double, y0: Double, y1: Double) -> StrokeData {
        StrokeData(
            points: [
                StrokePoint(location: Point(x: x0, y: y0), timestampOffset: 0, width: 2, force: 0.5, azimuth: 0, altitude: 0),
                StrokePoint(location: Point(x: x1, y: y1), timestampOffset: 0.1, width: 2, force: 0.5, azimuth: 0, altitude: 0),
            ],
            colorHex: "#000000",
            baseWidth: 2
        )
    }

    private func addStrokeBlock(_ stroke: StrokeData, frame: Rect) throws -> CanvasBlock {
        try store.addBlock(in: recordID, kind: .stroke, frame: frame,
                           payload: .stroke([stroke], recognizedText: "", corrected: false))
    }

    func testCommitNormalizesLineTo12pxInPlace() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        // Two raw strokes forming a 40px-tall line.
        let a = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                                   frame: Rect(x: 10, y: 100, width: 20, height: 40))
        let b = try addStrokeBlock(stroke(x0: 35, x1: 55, y0: 105, y1: 140),
                                   frame: Rect(x: 35, y: 105, width: 20, height: 35))

        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 100)
        session.letterCursor = Point(x: 0, y: 90)
        session.letterLineStartCount = 0
        session.commitLetterLine()

        // Same two blocks (stable IDs/counts so undo math holds), uniformly
        // scaled so the line union is ~12px tall (proportions preserved).
        let strokes = try store.strokeBlocks(in: recordID)
        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(Set(strokes.map(\.id)), [a.id, b.id])
        var union = Rect.zero
        var first = true
        for block in strokes {
            guard case .stroke(let list, _, _) = block.payload, let s = list.first else {
                return XCTFail("expected stroke payload")
            }
            union = first ? s.bounds : Rect.union(union, s.bounds)
            first = false
            XCTAssertGreaterThanOrEqual(s.bounds.minX, 0)
        }
        XCTAssertEqual(union.size.height, 12, accuracy: 0.001)
        let bHeight = strokes.first { $0.id == b.id }.flatMap { block -> Double? in
            guard case .stroke(let list, _, _) = block.payload else { return nil }
            return list.first?.bounds.size.height
        }
        XCTAssertEqual(bHeight ?? -1, 10.5, accuracy: 0.001, "35px stroke scaled by 12/40")
        XCTAssertEqual(session.drawingRewriteToken, 1, "canvas must rebuild from the store")
        // 45px-wide union scaled by 12/40 advances x by 13.5 + proportional gap (0.4×12=4.8).
        XCTAssertEqual(session.letterCursor.x, 18.3, accuracy: 1e-9)
        XCTAssertEqual(session.letterCursor.y, 90, accuracy: 1e-9)
        XCTAssertEqual(session.letterLineStartCount, 2)
        // Ink width scales with the geometry — unscaled would render fat letters.
        for block in strokes {
            guard case .stroke(let list, _, _) = block.payload, let s = list.first else {
                return XCTFail("expected stroke payload")
            }
            XCTAssertEqual(s.baseWidth, 0.6, accuracy: 0.001)
            XCTAssertTrue(s.points.allSatisfy { abs($0.width - 0.6) < 0.001 })
        }
    }

    func testCommitSkipsStrokesOutsideArea() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        let inside = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                                        frame: Rect(x: 10, y: 100, width: 20, height: 40))
        let outside = try addStrokeBlock(stroke(x0: 500, x1: 520, y0: 500, y1: 540),
                                         frame: Rect(x: 500, y: 500, width: 20, height: 40))

        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 100)
        session.letterCursor = Point(x: 0, y: 90)
        session.letterLineStartCount = 0
        session.commitLetterLine()

        let strokes = try store.strokeBlocks(in: recordID)
        XCTAssertEqual(strokes.count, 2)
        let kept = strokes.first { $0.id == outside.id }
        guard case .stroke(let list, _, _) = kept?.payload, let s = list.first else {
            return XCTFail("expected stroke payload")
        }
        XCTAssertEqual(s.bounds.size.height, 40, accuracy: 0.001, "outside strokes stay raw")
        XCTAssertEqual(inside.id, strokes.first { $0.id == inside.id }?.id)
    }

    func testCommitWrapsAtAreaEdge() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        _ = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                               frame: Rect(x: 10, y: 100, width: 20, height: 40))
        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 100)
        session.letterCursor = Point(x: 190, y: 90)
        session.letterLineStartCount = 0
        session.commitLetterLine()

        // 190 + 20*0.3 + 0.4*12 = 200.8 >= 200 - 4.8 → wrap to the next line.
        XCTAssertEqual(session.letterCursor.x, 0, accuracy: 1e-9)
        XCTAssertEqual(session.letterCursor.y, 90 + LetterMode.lineGap(targetHeight: 12) + 12, accuracy: 1e-9)
    }

    func testCommitAnchorsBaselineAndLeavesRoomForDescenders() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        // Normal letter (10..30 x, 100..140 y) and a separate j-tail stroke
        // reaching 20px past the common bottom.
        _ = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                               frame: Rect(x: 10, y: 100, width: 20, height: 40))
        _ = try addStrokeBlock(stroke(x0: 50, x1: 70, y0: 130, y1: 160),
                               frame: Rect(x: 50, y: 130, width: 20, height: 30))
        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 120)
        session.letterCursor = Point(x: 0, y: 90)
        session.letterLineStartCount = 0
        session.commitLetterLine()

        let strokes = try store.strokeBlocks(in: recordID)
        var normalBounds: Rect?
        var tailBounds: Rect?
        for block in strokes {
            guard case .stroke(let list, _, _) = block.payload, let s = list.first else {
                return XCTFail("expected stroke payload")
            }
            // Mapped coordinates: the letter sits at cursor.x (0..6), the
            // tail further right (12..18).
            if s.bounds.maxX <= 8 { normalBounds = s.bounds } else { tailBounds = s.bounds }
        }
        // Body letters fill exactly [cursor.y, cursor.y + 12]; the tail hangs
        // below the committed baseline instead of squashing the whole line.
        XCTAssertEqual(try XCTUnwrap(normalBounds).size.height, 12, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(normalBounds).minY, 90, accuracy: 0.001)
        let tail = try XCTUnwrap(tailBounds)
        XCTAssertGreaterThan(tail.maxY, 102, "descender extends below the committed baseline")
        // Tail keeps its scaled proportions (not compacted): 30px × 12/40.
        XCTAssertEqual(tail.size.height, 9, accuracy: 0.001)
    }

    func testLateDiacriticFoldsIntoLastCommittedLetter() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        // Letter commits alone.
        _ = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                               frame: Rect(x: 10, y: 100, width: 20, height: 40))
        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 120)
        session.letterCursor = Point(x: 0, y: 90)
        session.letterLineStartCount = 0
        session.commitLetterLine()
        XCTAssertEqual(try store.strokeBlocks(in: recordID).count, 1)
        let cursorAfterLetter = session.letterCursor.x

        // The i-dot drawn later, as its own commit — must fold on top of the
        // letter, not become an inflated blob of its own.
        let dot = try addStrokeBlock(
            stroke(x0: 15, x1: 16, y0: 88, y1: 90),
            frame: Rect(x: 15, y: 88, width: 1, height: 2)
        )
        session.letterLineStartCount = 1
        session.commitLetterLine()

        let strokeCount = try store.strokeBlocks(in: recordID).count
        XCTAssertEqual(strokeCount, 2, "dot keeps its block, count stable")
        XCTAssertEqual(session.letterCursor.x, cursorAfterLetter, "cursor does not advance for a folded dot")
        let blocks = try store.strokeBlocks(in: recordID)
        let dotPayload = blocks.first { $0.id == dot.id }
        guard case .stroke(let list, _, _) = dotPayload?.payload, let dotInk = list.first else {
            return XCTFail("expected dot stroke payload")
        }
        XCTAssertTrue(dotInk.bounds.maxY < 90, "dot folded above the committed letter's top")
        // DOT: raw width 1 → 0.3, centered over the 6px-wide letter.
        XCTAssertEqual(dotInk.bounds.minX, letterFoldX(width: 6, dotW: dotInk.bounds.size.width), accuracy: 0.001)
    }

    /// X position the folding math should produce: centered over the letter.
    private func letterFoldX(width: Double, dotW: Double) -> Double { (width - dotW) / 2 }

    func testBackspaceDeletesLastCommittedLetterAndRestoresCursor() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.letterArea = Rect(x: 0, y: 90, width: 200, height: 200)
        session.letterCursor = Point(x: 0, y: 90)
        session.letterLineStartCount = 0

        let first = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                                       frame: Rect(x: 10, y: 100, width: 20, height: 40))
        session.commitLetterLine()
        let secondCursorX = session.letterCursor.x
        _ = try addStrokeBlock(stroke(x0: 10, x1: 30, y0: 100, y1: 140),
                               frame: Rect(x: 10, y: 100, width: 20, height: 40))
        session.commitLetterLine()
        XCTAssertEqual(try store.strokeBlocks(in: recordID).count, 2)

        session.letterBackspace()

        let remaining = try store.strokeBlocks(in: recordID)
        XCTAssertEqual(remaining.count, 1, "backspace deletes the last committed letter's blocks")
        XCTAssertEqual(remaining.first?.id, first.id)
        XCTAssertEqual(session.letterCursor.x, secondCursorX, accuracy: 1e-9)
        XCTAssertEqual(session.letterCursor.y, 90, accuracy: 1e-9)

        session.letterBackspace()
        XCTAssertEqual(try store.strokeBlocks(in: recordID).count, 0)
    }

    func testTrackLetterWritingFollowsCamera() {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.viewport = Size(width: 800, height: 600)
        session.letterArea = Rect(x: 0, y: 0, width: 200, height: 200)

        session.trackLetterWriting(x: 100, y: 100)
        XCTAssertEqual(session.transform.offsetX, 0, accuracy: 1e-9, "below threshold: no pan")

        session.trackLetterWriting(x: 700, y: 100)
        XCTAssertEqual(session.transform.offsetX, -140, accuracy: 1e-9, "writing parks at 70% width")
    }
}

final class LiveStrokeTests: XCTestCase {
    func testLiveStrokeSetAndClear() {
        let store = InkStrokeStore()
        XCTAssertNil(store.liveStroke)
        let preview = StrokeData(
            points: [StrokePoint(location: Point(x: 1, y: 2), timestampOffset: 0, width: 2, force: 0.5, azimuth: 0, altitude: 0)],
            colorHex: "#FF0000",
            baseWidth: 2
        )
        store.setLiveStroke(preview)
        XCTAssertEqual(store.liveStroke, preview)
        store.clearLiveStroke()
        XCTAssertNil(store.liveStroke)
    }

    func testLiveStrokeReplacesPreviousPreview() {
        let store = InkStrokeStore()
        let first = StrokeData(points: [], colorHex: "#000000", baseWidth: 2)
        let second = StrokeData(points: [], colorHex: "#FFFFFF", baseWidth: 3)
        store.setLiveStroke(first)
        store.setLiveStroke(second)
        XCTAssertEqual(store.liveStroke, second)
        // Completed strokes are untouched by the ephemeral preview.
        XCTAssertTrue(store.strokes.isEmpty)
    }
}
