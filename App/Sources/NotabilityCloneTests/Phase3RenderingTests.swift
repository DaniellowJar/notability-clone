import NotabilityCore
import PencilKit
import XCTest
@testable import NotabilityClone

final class Phase3RenderingTests: XCTestCase {
    private func drawingWithOneStroke() -> PKDrawing {
        let point = PKStrokePoint(
            location: CGPoint(x: 10, y: 10), timeOffset: 0,
            size: CGSize(width: 3, height: 3), opacity: 1,
            force: 1, azimuth: 0, altitude: 90
        )
        let path = PKStrokePath(controlPoints: [point], creationDate: Date())
        let ink = PKInk(.pen, color: .black)
        return PKDrawing(strokes: [PKStroke(ink: ink, path: path)])
    }

    func testStrokeConverterRoundTrip() {
        let drawing = drawingWithOneStroke()
        let data = PKStrokeConverter.strokeData(from: drawing.strokes[0])
        XCTAssertFalse(data.points.isEmpty)
        XCTAssertFalse(data.colorHex.isEmpty)
        XCTAssertGreaterThan(data.baseWidth, 0)

        let rebuilt = PKStrokeConverter.drawing(from: [data])
        XCTAssertEqual(rebuilt.strokes.count, 1)
    }

    func testDrawingMigratorConvertsBlobToStrokeBlocks() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.saveDrawingData(drawingWithOneStroke().dataRepresentation(), for: rec.id)

        XCTAssertTrue(DrawingMigrator.migrateIfNeeded(recordID: rec.id, store: store))
        XCTAssertNil(try store.drawingData(for: rec.id), "blob cleared after migration")
        XCTAssertEqual(try store.strokeBlocks(in: rec.id).count, 1)
    }

    func testDrawingMigratorIsIdempotent() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        try store.saveDrawingData(drawingWithOneStroke().dataRepresentation(), for: rec.id)

        _ = DrawingMigrator.migrateIfNeeded(recordID: rec.id, store: store)
        XCTAssertFalse(DrawingMigrator.migrateIfNeeded(recordID: rec.id, store: store),
                       "second migration must no-op")
        XCTAssertEqual(try store.strokeBlocks(in: rec.id).count, 1)
    }

    func testSessionReloadExcludesStrokeBlocks() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        let stroke = StrokeData(
            points: [StrokePoint(location: Point(x: 0, y: 0), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45)],
            colorHex: "#000", baseWidth: 2
        )
        _ = try store.addBlock(in: rec.id, kind: .stroke, frame: .zero, payload: .stroke([stroke], recognizedText: "", corrected: false))
        _ = try store.addBlock(in: rec.id, kind: .text, frame: .zero, payload: .text(TextBlockPayload(text: "x")))

        let session = CanvasSessionState()
        session.load(recordID: rec.id, store: store)
        XCTAssertEqual(session.blocks.count, 1, "ink strokes render via the ink layer, not the block overlay")
        XCTAssertEqual(session.blocks[0].kind, .text)
    }

    func testInkBackingScaleTracksZoom() {
        // The raster backing must match display × zoom so zoomed ink
        // re-rasterizes from vectors instead of magnifying a 1x bitmap.
        let view = InkCanvasView()
        let screen = Double(UIScreen.main.scale)
        view.zoomScale = 1
        XCTAssertEqual(Double(view.contentScaleFactor), screen * 1, accuracy: 0.001)
        view.zoomScale = 2
        XCTAssertEqual(Double(view.contentScaleFactor), screen * 2, accuracy: 0.001)
    }
}
