import XCTest
@testable import NotabilityCore

final class SlantEstimatorTests: XCTestCase {
    private func points(_ values: [(Double, Double)]) -> [StrokePoint] {
        values.map { StrokePoint(location: Point(x: $0.0, y: $0.1), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45) }
    }

    func testUprightStrokeHasZeroSlant() {
        let p = points([(0, 0), (0, 5), (0, 10), (0, 15), (0, 20)])
        XCTAssertEqual(SlantEstimator.estimate(p), 0, accuracy: 0.001)
    }

    func testLeaningStrokeHasPositiveSlant() {
        // Top at x=2, bottom at x=0.8 → leaning right.
        let p = points([(2, 0), (1.7, 5), (1.4, 10), (1.1, 15), (0.8, 20)])
        XCTAssertGreaterThan(SlantEstimator.estimate(p), 0)
    }

    func testHorizontalStrokeIgnored() {
        let p = points([(0, 5), (5, 5), (10, 5), (15, 5)])
        XCTAssertEqual(SlantEstimator.estimate(p), 0, accuracy: 0.001)
    }
}

final class StrokeCorrectionTests: XCTestCase {
    private func stroke(_ values: [(Double, Double)]) -> StrokeData {
        StrokeData(
            points: values.map { StrokePoint(location: Point(x: $0.0, y: $0.1), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45) },
            colorHex: "#000",
            baseWidth: 2
        )
    }

    func testStraightensLeaningStroke() {
        let leaning = stroke([(2, 0), (1.7, 5), (1.4, 10), (1.1, 15), (0.8, 20)])
        let corrected = StrokeCorrection.correct(leaning)
        guard let points = corrected.correctedPoints else {
            return XCTFail("expected correctedPoints")
        }
        let firstX = points[0].location.x
        let lastX = points[points.count - 1].location.x
        XCTAssertEqual(firstX, lastX, accuracy: 0.01, "top and bottom should align (upright)")
        XCTAssertEqual(corrected.transform?.slant ?? 0, 0.06, accuracy: 0.05)
    }

    func testUprightStrokeUnchanged() {
        let upright = stroke([(0, 0), (0, 5), (0, 10), (0, 15), (0, 20)])
        let corrected = StrokeCorrection.correct(upright)
        guard let points = corrected.correctedPoints else {
            return XCTFail("expected correctedPoints")
        }
        XCTAssertEqual(points.first?.location.x ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(points.last?.location.x ?? -1, 0, accuracy: 0.001)
    }

    func testSnapsToReferenceBaseline() {
        let upright = stroke([(0, 0), (0, 20)])
        let corrected = StrokeCorrection.correct(upright, referenceBaselineY: 100)
        guard let points = corrected.correctedPoints else {
            return XCTFail("expected correctedPoints")
        }
        XCTAssertEqual(points.last?.location.y ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(corrected.transform?.baselineAdjustment ?? 0, 80, accuracy: 0.001)
    }

    func testCorrectionPreservesHeight() {
        let leaning = stroke([(2, 0), (1.4, 10), (0.8, 20)])
        let corrected = StrokeCorrection.correct(leaning)
        guard let points = corrected.correctedPoints else { return XCTFail("no points") }
        let height = (points.map { $0.location.y }.max() ?? 0) - (points.map { $0.location.y }.min() ?? 0)
        XCTAssertEqual(height, 20, accuracy: 0.001)
    }

    func testSinglePointStrokeUnchanged() {
        let single = StrokeData(
            points: [StrokePoint(location: Point(x: 1, y: 1), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45)],
            colorHex: "#000", baseWidth: 2
        )
        XCTAssertEqual(StrokeCorrection.correct(single), single)
    }
}

final class RecognitionPlanTests: XCTestCase {
    private func strokeBlock(recognized: String) -> CanvasBlock {
        CanvasBlock(
            recordId: UUID(), kind: .stroke,
            frame: .zero, zIndex: 1, timestamp: Date(),
            payload: .stroke(
                [StrokeData(points: [StrokePoint(location: Point(x: 0, y: 0), timestampOffset: 0, width: 2, force: 1, azimuth: 0, altitude: 45)], colorHex: "#000", baseWidth: 2)],
                recognizedText: recognized, corrected: false
            )
        )
    }

    func testPendingFiltersUnrecognized() {
        let blocks = [strokeBlock(recognized: ""), strokeBlock(recognized: "hello"), strokeBlock(recognized: "")]
        XCTAssertEqual(RecognitionPlan.pending(in: blocks).count, 2)
        XCTAssertEqual(RecognitionPlan.recognizedCount(in: blocks), 1)
    }

    func testWithRecognizedTextMergesAndKeepsCorrectedFlag() {
        let block = strokeBlock(recognized: "")
        let updated = RecognitionPlan.withRecognizedText("hello", on: block)
        guard case .stroke(_, let text, let corrected) = updated.payload else {
            return XCTFail("expected stroke payload")
        }
        XCTAssertEqual(text, "hello")
        XCTAssertFalse(corrected)
    }

    func testWithCorrectedSetsFlagKeepsText() {
        let block = strokeBlock(recognized: "hi")
        let updated = RecognitionPlan.withCorrected(true, on: block)
        guard case .stroke(_, let text, let corrected) = updated.payload else {
            return XCTFail("expected stroke payload")
        }
        XCTAssertEqual(text, "hi")
        XCTAssertTrue(corrected)
    }
}
