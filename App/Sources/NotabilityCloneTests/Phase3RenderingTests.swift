import NotabilityCore
import PencilKit
import UIKit
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

    func testInkRendersVectorLayers() {
        // Strokes must render as vector CAShapeLayers (Core Animation
        // rasterizes them at the composited resolution) rather than a 1x
        // backing store that the parent zoom would magnify into pixels.
        let view = InkCanvasView()
        let stroke = StrokeData(
            points: [
                StrokePoint(location: Point(x: 0, y: 0), timestampOffset: 0, width: 3, force: 1, azimuth: 0, altitude: 45),
                StrokePoint(location: Point(x: 10, y: 10), timestampOffset: 0, width: 3, force: 1, azimuth: 0, altitude: 45),
            ],
            colorHex: "#FF0000", baseWidth: 3
        )
        view.strokes = [stroke]

        let shapes = (view.layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        let strokeLayers = shapes.filter { $0.path != nil }
        XCTAssertEqual(strokeLayers.count, 1, "each stroke is a vector CAShapeLayer")
        XCTAssertEqual(Double(strokeLayers[0].lineWidth), 3, accuracy: 0.001)
        XCTAssertNotNil(strokeLayers[0].strokeColor)

        // Vector layers are resolution-independent, so zoom must not require a
        // backing-store rescale.
        let backingScale = view.contentScaleFactor
        view.zoomScale = 2
        XCTAssertEqual(view.contentScaleFactor, backingScale, "zoom must not rescale the backing store")
    }
}
