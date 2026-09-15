import XCTest
import Foundation
@testable import NotabilityCore

final class NotebookCRUDTests: XCTestCase {
    func testCreateAndFetchNotebooks() throws {
        let store = try NotabilityStore()
        let a = try store.createNotebook(title: "Math", coverColorHex: "#FF6600")
        let b = try store.createNotebook(title: "Physics", coverColorHex: "#3366FF")

        let all = try store.allNotebooks()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(Set(all.map(\.id)), [a.id, b.id])
        XCTAssertEqual(all.first { $0.id == a.id }?.title, "Math")
        XCTAssertEqual(all.first { $0.id == a.id }?.coverColorHex, "#FF6600")
    }

    func testRenameNotebook() throws {
        let store = try NotabilityStore()
        let a = try store.createNotebook(title: "Old", coverColorHex: "#000000")
        try store.renameNotebook(a.id, title: "New")
        let fetched = try store.allNotebooks().first { $0.id == a.id }
        XCTAssertEqual(fetched?.title, "New")
    }

    func testDeleteNotebook() throws {
        let store = try NotabilityStore()
        let a = try store.createNotebook(title: "A", coverColorHex: "#000000")
        _ = try store.createNotebook(title: "B", coverColorHex: "#000000")
        try store.deleteNotebook(a.id)
        let all = try store.allNotebooks()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all.contains { $0.id == a.id })
    }

    func testCreateRecordRequiresNotebook() throws {
        let store = try NotabilityStore()
        XCTAssertThrowsError(try store.createRecord(in: UUID(), title: "orphan")) { error in
            guard case SchemaError.notebookMissing = error else {
                return XCTFail("expected notebookMissing, got \(error)")
            }
        }
    }
}

final class RecordCRUDTests: XCTestCase {
    func testRecordsNestedUnderNotebook() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let other = try store.createNotebook(title: "Other", coverColorHex: "#000")
        let r1 = try store.createRecord(in: nb.id, title: "Lesson 1")
        _ = try store.createRecord(in: nb.id, title: "Lesson 2")
        _ = try store.createRecord(in: other.id, title: "nope")

        let recs = try store.records(in: nb.id)
        XCTAssertEqual(recs.count, 2)
        XCTAssertTrue(recs.allSatisfy { $0.notebookId == nb.id })
        XCTAssertEqual(recs.first { $0.id == r1.id }?.title, "Lesson 1")
    }

    func testDeleteRecord() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.deleteRecord(rec.id)
        XCTAssertTrue(try store.records(in: nb.id).isEmpty)
    }
}

final class BlockCRUDTests: XCTestCase {
    var store: NotabilityStore!
    var notebookID: UUID!
    var recordID: UUID!

    override func setUp() {
        super.setUp()
        store = try! NotabilityStore()
        notebookID = try! store.createNotebook(title: "NB", coverColorHex: "#000").id
        recordID = try! store.createRecord(in: notebookID, title: "rec").id
    }

    private func add(block: BlockPayload, frame: Rect = Rect(x: 10, y: 20, width: 100, height: 50)) throws -> CanvasBlock {
        try store.addBlock(in: recordID, kind: block.kind, frame: frame, payload: block)
    }

    func testStrokeBlockRoundTrip() throws {
        let stroke = StrokeData(
            points: [
                StrokePoint(location: Point(x: 0, y: 0), timestampOffset: 0, width: 2, force: 0.5, azimuth: 0, altitude: 45),
                StrokePoint(location: Point(x: 5, y: 8), timestampOffset: 0.05, width: 3, force: 1, azimuth: 0.1, altitude: 50),
                StrokePoint(location: Point(x: 10, y: 16), timestampOffset: 0.10, width: 2, force: 0.7, azimuth: 0.2, altitude: 55)
            ],
            colorHex: "#000FFF",
            baseWidth: 2.5
        )
        let block = try add(block: .stroke([stroke], recognizedText: "hello", corrected: false))
        let stored = try store.block(id: block.id)
        guard case let .stroke(strokes, text, corrected) = stored?.payload else {
            return XCTFail("expected .stroke payload")
        }
        XCTAssertEqual(strokes, [stroke])
        XCTAssertEqual(text, "hello")
        XCTAssertFalse(corrected)
    }

    func testAllBlockKindsRoundTrip() throws {
        let kinds: [BlockPayload] = [
            .stroke([], recognizedText: "x", corrected: true),
            .text(TextBlockPayload(text: "typed note", fontSize: 19, colorHex: "#FF0000", bold: true)),
            .image(ImageBlockPayload(imageRef: "img-1", cropRect: Rect(x: 0, y: 0, width: 0.5, height: 0.5), backgroundRemoved: true)),
            .pdfPage(PDFPageBlockPayload(sourcePDFRef: "pdf-1", pageIndex: 3, renderedImageRef: "img-2")),
            .calc(CalcBlockPayload(expression: "300 x 2", result: "600", isEditable: false)),
            .mathAI(MathAIBlockPayload(sourceStrokeBlockID: UUID(), latex: "x^2", steps: ["factor"], variables: ["a": 2.0]))
        ]
        for payload in kinds {
            let block = try add(block: payload)
            let stored = try store.block(id: block.id)
            XCTAssertEqual(stored?.payload, payload, "round-trip failed for \(payload.kind)")
            XCTAssertEqual(stored?.kind, payload.kind)
        }
    }

    func testTimestampAssignmentsAreMonotonic() throws {
        let t1 = Date(timeIntervalSince1970: 100)
        let t2 = Date(timeIntervalSince1970: 200)
        let t3 = Date(timeIntervalSince1970: 150) // intentionally out of order
        let b1 = try store.addBlock(in: recordID, kind: .calc, frame: .zero, payload: .calc(CalcBlockPayload(expression: "1+1")), at: t1)
        let b2 = try store.addBlock(in: recordID, kind: .calc, frame: .zero, payload: .calc(CalcBlockPayload(expression: "2+2")), at: t2)
        let b3 = try store.addBlock(in: recordID, kind: .calc, frame: .zero, payload: .calc(CalcBlockPayload(expression: "3+3")), at: t3)

        // Timestamps come straight back — creation-order independent.
        XCTAssertEqual(b1.timestamp, t1)
        XCTAssertEqual(b3.timestamp, t3)
        XCTAssertEqual(b2.timestamp, t2)
    }

    func testZIndexAutoIncrement() throws {
        _ = try add(block: .calc(CalcBlockPayload(expression: "1")))
        _ = try add(block: .calc(CalcBlockPayload(expression: "2")))
        _ = try add(block: .calc(CalcBlockPayload(expression: "3")))
        let blocks = try store.blocks(in: recordID)
        XCTAssertEqual(blocks.map(\.zIndex), [1, 2, 3])
    }

    func testUpdateFrameAndPayload() throws {
        let block = try add(block: .text(TextBlockPayload(text: "a")))
        let newFrame = Rect(x: 99, y: 88, width: 20, height: 30)
        try store.updateBlockFrame(block.id, frame: newFrame)
        try store.updateBlockPayload(block.id, payload: .text(TextBlockPayload(text: "b")))

        let stored = try store.block(id: block.id)
        XCTAssertEqual(stored?.frame, newFrame)
        guard case let .text(payload) = stored?.payload else { return XCTFail("expected text") }
        XCTAssertEqual(payload.text, "b")
    }

    func testDeleteBlock() throws {
        let block = try add(block: .text(TextBlockPayload(text: "a")))
        try store.deleteBlock(block.id)
        XCTAssertNil(try store.block(id: block.id))
    }
}

final class CascadeAndPersistenceTests: XCTestCase {
    func testDeletingRecordCascadesBlocks() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        _ = try store.addBlock(in: rec.id, kind: .text, frame: .zero, payload: .text(TextBlockPayload(text: "x")))
        _ = try store.addBlock(in: rec.id, kind: .image, frame: .zero, payload: .image(ImageBlockPayload(imageRef: "i")))
        try store.deleteRecord(rec.id)
        XCTAssertTrue(try store.blocks(in: rec.id).isEmpty)
    }

    func testDeletingNotebookCascadesRecordsAndBlocks() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        _ = try store.addBlock(in: rec.id, kind: .calc, frame: .zero, payload: .calc(CalcBlockPayload(expression: "1")))
        try store.deleteNotebook(nb.id)
        XCTAssertTrue(try store.records(in: nb.id).isEmpty)
        XCTAssertTrue(try store.blocks(in: rec.id).isEmpty)
    }

    func testPersistenceAcrossReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("store.sqlite").path
        defer { try? FileManager.default.removeItem(at: dir) }

        var notebookID: UUID!
        do {
            let store = try NotabilityStore(path: path)
            let nb = try store.createNotebook(title: "Persisted", coverColorHex: "#00AA00")
            notebookID = nb.id
            let rec = try store.createRecord(in: nb.id, title: "rec")
            _ = try store.addBlock(in: rec.id, kind: .text, frame: Rect(x: 1, y: 2, width: 3, height: 4), payload: .text(TextBlockPayload(text: "survives restart")))
        }

        let reopened = try NotabilityStore(path: path)
        let notebooks = try reopened.allNotebooks()
        XCTAssertEqual(notebooks.count, 1)
        let recs = try reopened.records(in: notebookID)
        XCTAssertEqual(recs.first?.title, "rec")
        let blocks = try reopened.blocks(in: recs[0].id)
        XCTAssertEqual(blocks.first?.frame, Rect(x: 1, y: 2, width: 3, height: 4))
    }

    func testAudioTrackRoundTrip() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        let recordedAt = Date(timeIntervalSince1970: 1700)
        try store.setAudioTrack(AudioTrack(fileRef: "audio-1.m4a", duration: 91.5, recordedAt: recordedAt), for: rec.id)
        let track = try store.audioTrack(for: rec.id)
        XCTAssertEqual(track?.fileRef, "audio-1.m4a")
        XCTAssertEqual(track?.duration, 91.5)
        XCTAssertEqual(track?.recordedAt, recordedAt)
    }

    func testTranscriptPersistsInOrder() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.appendTranscriptSegment(TranscriptSegment(recordId: rec.id, seq: 0, text: "first", startTime: 0, endTime: 2))
        try store.appendTranscriptSegment(TranscriptSegment(recordId: rec.id, seq: 1, text: "second", startTime: 2, endTime: 5))
        try store.appendTranscriptSegment(TranscriptSegment(recordId: rec.id, seq: 2, text: "third", startTime: 5, endTime: 8))

        let transcript = try store.transcript(for: rec.id)
        XCTAssertEqual(transcript.segments.map(\.text), ["first", "second", "third"])

        // Shared-clock lookup on the transcript model.
        XCTAssertEqual(transcript.segments(overlapping: 3.5).map(\.text), ["second"])
        XCTAssertEqual(transcript.segments(overlapping: 7.9).map(\.text), ["third"])
        XCTAssertTrue(transcript.segments(overlapping: 100).isEmpty)
    }
}

final class DrawingPersistenceTests: XCTestCase {
    func testDrawingBlobRoundTrip() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")

        XCTAssertNil(try store.drawingData(for: rec.id), "fresh record has no drawing")

        let data = Data([0, 42, 255, 1, 2, 3])
        try store.saveDrawingData(data, for: rec.id)
        XCTAssertEqual(try store.drawingData(for: rec.id), data)
    }

    func testSaveDrawingBumpsModifiedAt() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")

        let before = try store.records(in: nb.id)[0].modifiedAt
        try store.saveDrawingData(Data([7, 8]), for: rec.id)
        let after = try store.records(in: nb.id)[0].modifiedAt
        XCTAssertGreaterThan(after, before)
    }

    func testDrawingBlobSurvivesReopen() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("store.sqlite").path
        defer { try? FileManager.default.removeItem(at: dir) }

        let recID: UUID
        do {
            let store = try NotabilityStore(path: path)
            let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
            recID = try store.createRecord(in: nb.id, title: "r").id
            try store.saveDrawingData(Data([0, 1, 2, 255]), for: recID)
        }

        let reopened = try NotabilityStore(path: path)
        XCTAssertEqual(try reopened.drawingData(for: recID), Data([0, 1, 2, 255]))
    }

    func testDeleteRecordRemovesDrawing() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.saveDrawingData(Data([1]), for: rec.id)
        try store.deleteRecord(rec.id)
        XCTAssertNil(try store.drawingData(for: rec.id))
    }

    func testClearDrawingData() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.saveDrawingData(Data([1, 2]), for: rec.id)
        try store.clearDrawingData(for: rec.id)
        XCTAssertNil(try store.drawingData(for: rec.id))
    }

    func testStrokeBlocksReturnedInCaptureOrder() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        let t0 = Date(timeIntervalSince1970: 100)
        let stroke = StrokeData(points: [StrokePoint(location: Point(x: 0, y: 0), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45)], colorHex: "#000", baseWidth: 2)
        _ = try store.addBlock(in: rec.id, kind: .stroke, frame: .zero, payload: .stroke([stroke], recognizedText: "", corrected: false), at: t0)
        _ = try store.addBlock(in: rec.id, kind: .stroke, frame: .zero, payload: .stroke([stroke], recognizedText: "", corrected: false), at: t0.addingTimeInterval(1))
        _ = try store.addBlock(in: rec.id, kind: .text, frame: .zero, payload: .text(TextBlockPayload(text: "x")), at: t0.addingTimeInterval(0.5))

        let strokes = try store.strokeBlocks(in: rec.id)
        XCTAssertEqual(strokes.count, 2)
        XCTAssertTrue(strokes.allSatisfy { $0.kind == .stroke })
        XCTAssertEqual(strokes[0].timestamp, t0)
        XCTAssertEqual(strokes[1].timestamp, t0.addingTimeInterval(1))
    }
}

final class StrokeMathTests: XCTestCase {
    func testStrokeBounds() {
        let stroke = StrokeData(
            points: [
                StrokePoint(location: Point(x: -5, y: 10), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 0),
                StrokePoint(location: Point(x: 0, y: -3), timestampOffset: 0.1, width: 2, force: 1, azimuth: 0, altitude: 0),
                StrokePoint(location: Point(x: 20, y: 5), timestampOffset: 0.2, width: 2, force: 1, azimuth: 0, altitude: 0)
            ],
            colorHex: "#000",
            baseWidth: 2
        )
        let bounds = stroke.bounds
        XCTAssertEqual(bounds.minX, -5, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, -3, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxX, 20, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, 10, accuracy: 0.0001)
    }

    func testStrokeSimplificationRemovesCollinearPoints() {
        let points = (0...10).map { i in
            StrokePoint(location: Point(x: Double(i), y: 0), timestampOffset: Double(i) * 0.1, width: 2, force: 1, azimuth: 0, altitude: 0)
        }
        let stroke = StrokeData(points: points, colorHex: "#000", baseWidth: 2)
        let simplified = stroke.simplified(threshold: 2.0)
        // Collinear points spaced 1pt apart are dropped aggressively.
        XCTAssertLessThan(simplified.points.count, points.count)
    }

    func testRectUnionAndContains() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        let u = Rect.union(a, b)
        XCTAssertEqual(u.origin, Point(x: 0, y: 0))
        XCTAssertEqual(u.size, Size(width: 15, height: 15))
        XCTAssertTrue(u.contains(Point(x: 14, y: 14)))
        XCTAssertFalse(u.contains(Point(x: 15, y: 0)))
    }
}