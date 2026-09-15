import XCTest
@testable import NotabilityCore

final class StrokeCollectionTests: XCTestCase {
    private func stroke(x: Double = 0, y: Double = 0, len: Int = 2) -> StrokeData {
        StrokeData(
            points: (0..<len).map { i in
                StrokePoint(location: Point(x: x + Double(i), y: y), timestampOffset: Double(i) * 0.01,
                            width: 2, force: 1, azimuth: 0, altitude: 45)
            },
            colorHex: "#000000",
            baseWidth: 2
        )
    }

    func testAppendAndCount() {
        var collection = StrokeCollection()
        collection.append(stroke())
        collection.append(contentsOf: [stroke(x: 10), stroke(x: 20)])
        XCTAssertEqual(collection.count, 3)
        XCTAssertFalse(collection.isEmpty)
    }

    func testBoundsUnion() {
        var collection = StrokeCollection()
        collection.append(stroke(x: 0, y: 0))
        collection.append(stroke(x: 50, y: 30))
        let bounds = collection.bounds
        XCTAssertEqual(bounds.minX, 0)
        XCTAssertEqual(bounds.maxX, 51, accuracy: 0.0001)
        XCTAssertEqual(bounds.maxY, 30, accuracy: 0.0001)
    }

    func testEmptyBoundsIsZero() {
        XCTAssertEqual(StrokeCollection().bounds, .zero)
    }

    func testTruncateReturnsRemoved() {
        var collection = StrokeCollection(strokes: [stroke(x: 0), stroke(x: 10), stroke(x: 20)])
        let removed = collection.truncate(to: 1)
        XCTAssertEqual(collection.count, 1)
        XCTAssertEqual(removed.count, 2)
    }

    func testReconcileAddsNewStrokes() {
        var collection = StrokeCollection()
        let new = [stroke(x: 5), stroke(x: 6)]
        let result = collection.reconcile(observedCount: 2, newStrokes: new)
        XCTAssertEqual(result, .added(new))
        XCTAssertEqual(collection.count, 2)
    }

    func testReconcileTruncatesOnUndo() {
        var collection = StrokeCollection(strokes: [stroke(x: 0), stroke(x: 10), stroke(x: 20)])
        let result = collection.reconcile(observedCount: 1, newStrokes: [])
        guard case .removed(let removed) = result else {
            return XCTFail("expected .removed")
        }
        XCTAssertEqual(removed.count, 2)
        XCTAssertEqual(collection.count, 1)
    }

    func testReconcileNoopWhenEqual() {
        var collection = StrokeCollection(strokes: [stroke(x: 0)])
        XCTAssertEqual(collection.reconcile(observedCount: 1, newStrokes: []), .none)
    }
}
