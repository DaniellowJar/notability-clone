import XCTest
@testable import NotabilityCore

final class CanvasTransformTests: XCTestCase {
    func testIdentityRoundTrip() {
        let t = CanvasTransform(scale: 2, offsetX: 10, offsetY: -5)
        let p = Point(x: 3, y: 7)
        let back = t.toCanvas(t.toScreen(p))
        XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
        XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
    }

    func testRectMappingScalesOriginAndSize() {
        let t = CanvasTransform(scale: 2, offsetX: 5, offsetY: -5)
        let s = t.toScreen(Rect(x: 10, y: 20, width: 100, height: 50))
        XCTAssertEqual(s.origin.x, 25, accuracy: 1e-9)
        XCTAssertEqual(s.origin.y, 35, accuracy: 1e-9)
        XCTAssertEqual(s.size.width, 200, accuracy: 1e-9)
        XCTAssertEqual(s.size.height, 100, accuracy: 1e-9)
        let back = t.toCanvas(s)
        XCTAssertEqual(back.origin.x, 10, accuracy: 1e-9)
        XCTAssertEqual(back.size.width, 100, accuracy: 1e-9)
    }

    func testClampsScale() {
        XCTAssertEqual(CanvasTransform.clampedScale(0.5), 1.0)
        XCTAssertEqual(CanvasTransform.clampedScale(10), 4.0)
        XCTAssertEqual(CanvasTransform.clampedScale(2.5), 2.5)
    }

    func testSnapsToOneNearFloor() {
        XCTAssertEqual(CanvasTransform.clampedScale(1.03), 1.0)
        XCTAssertEqual(CanvasTransform.clampedScale(1.2), 1.2)
    }

    func testZoomKeepsAnchorStable() {
        // The canvas point under the pinch anchor must not move on screen.
        let zoomed = CanvasTransform.identity.zoomed(to: 2, anchorScreen: Point(x: 100, y: 50))
        let held = zoomed.toScreen(Point(x: 100, y: 50))
        XCTAssertEqual(held.x, 100, accuracy: 1e-9)
        XCTAssertEqual(held.y, 50, accuracy: 1e-9)
    }

    func testPanAccumulates() {
        let t = CanvasTransform.identity.panned(by: Point(x: 5, y: -3)).panned(by: Point(x: 2, y: 2))
        XCTAssertEqual(t.offsetX, 7, accuracy: 1e-9)
        XCTAssertEqual(t.offsetY, -1, accuracy: 1e-9)
    }

    func testGrownHeight() {
        // Never shrinks.
        XCTAssertEqual(CanvasTransform.grownHeight(current: 2000, contentBottom: 100, viewportHeight: 800, padding: 200), 2000)
        // Pads below the lowest content.
        XCTAssertEqual(CanvasTransform.grownHeight(current: 500, contentBottom: 900, viewportHeight: 800, padding: 200), 1100)
        // Always covers the viewport.
        XCTAssertEqual(CanvasTransform.grownHeight(current: 100, contentBottom: 50, viewportHeight: 800, padding: 200), 800)
    }
}

final class PageHeaderFormatTests: XCTestCase {
    private let posix = Locale(identifier: "en_US_POSIX")
    private var gmt: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var ref: Date { Date(timeIntervalSinceReferenceDate: 0) } // 2001-01-01 00:00 GMT

    func testDefaultFormatsDate() {
        let s = PageHeaderFormat.default.formatted(date: ref, locale: posix, timeZone: gmt)
        XCTAssertTrue(s.contains("2001"), "got: \(s)")
        XCTAssertTrue(s.contains("·"), "date and time are joined, got: \(s)")
    }

    func testCustomFormat() {
        let f = PageHeaderFormat(alignment: .trailing, dateFormat: "yyyy-MM-dd", timeFormat: "HH:mm")
        XCTAssertEqual(f.formatted(date: ref, locale: posix, timeZone: gmt), "2001-01-01 · 00:00")
    }

    func testValidation() {
        XCTAssertFalse(PageHeaderFormat.isValidFormat(""))
        XCTAssertFalse(PageHeaderFormat.isValidFormat("   "))
        XCTAssertTrue(PageHeaderFormat.isValidFormat("MMM d, yyyy"))
    }

    func testAlignmentCodableRoundTrip() {
        let f = PageHeaderFormat(alignment: .trailing, dateFormat: "yyyy", timeFormat: "HH")
        let data = try! JSONEncoder().encode(f)
        let back = try! JSONDecoder().decode(PageHeaderFormat.self, from: data)
        XCTAssertEqual(back, f)
    }
}

final class LetterModeMathTests: XCTestCase {
    private func stroke(x0: Double, x1: Double) -> StrokeData {
        StrokeData(
            points: [
                StrokePoint(location: Point(x: x0, y: 0), timestampOffset: 0, width: 2, force: 0.5, azimuth: 0, altitude: 0),
                StrokePoint(location: Point(x: x1, y: 10), timestampOffset: 0.1, width: 2, force: 0.5, azimuth: 0, altitude: 0),
            ],
            colorHex: "#000000",
            baseWidth: 2
        )
    }

    func testZoomToFit() {
        XCTAssertEqual(LetterMode.zoomToFit(areaWidth: 200, viewportWidth: 800), 4.0, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.zoomToFit(areaWidth: 400, viewportWidth: 800), 2.0, accuracy: 1e-9)
        // Wider than the screen stays at original size (100% floor).
        XCTAssertEqual(LetterMode.zoomToFit(areaWidth: 1600, viewportWidth: 800), 1.0, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.zoomToFit(areaWidth: 0, viewportWidth: 800), 1.0, accuracy: 1e-9)
    }

    func testFollowOffsetAdvancesPastThreshold() {
        // Writing at 90% of an 800pt viewport at 2x must pull back to 70%.
        let offset = LetterMode.followOffset(writingCanvasX: 400, scale: 2, offsetX: 0, viewportWidth: 800)
        XCTAssertEqual(offset, -240, accuracy: 1e-9)
        // Sanity: the writing position now sits exactly at the threshold.
        XCTAssertEqual(400 * 2 + offset, 0.7 * 800, accuracy: 1e-9)
    }

    func testFollowOffsetHoldsBelowThreshold() {
        let offset = LetterMode.followOffset(writingCanvasX: 200, scale: 2, offsetX: 0, viewportWidth: 800)
        XCTAssertEqual(offset, 0, accuracy: 1e-9)
    }

    func testNormalizeScale() {
        XCTAssertEqual(LetterMode.normalizeScale(lineHeight: 48), 0.25, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.normalizeScale(lineHeight: 0), 1.0, accuracy: 1e-9)
    }

    func testLetterClustering() {
        let a = stroke(x0: 0, x1: 8)
        let b = stroke(x0: 10, x1: 18) // gap 2 → same letter as a
        let dot = stroke(x0: 4, x1: 6) // i-dot overlapping → same letter
        let c = stroke(x0: 40, x1: 48) // gap 22 → new letter
        let clusters = LetterMode.letterClusters(strokes: [a, b, dot, c])
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].count, 3)
        XCTAssertEqual(clusters[1].count, 1)
    }

    func testClusterAlphaRamp() {
        XCTAssertEqual(LetterMode.clusterAlpha(positionsBackFromNewest: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.clusterAlpha(positionsBackFromNewest: 1), 0.55, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.clusterAlpha(positionsBackFromNewest: 2), 0.25, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.clusterAlpha(positionsBackFromNewest: 3), 0, accuracy: 1e-9)
        XCTAssertEqual(LetterMode.clusterAlpha(positionsBackFromNewest: 10), 0, accuracy: 1e-9)
    }
}
