import XCTest
@testable import NotabilityCore

final class AreaSelectionTests: XCTestCase {
    func testNormalizeReordersArbitraryDrag() {
        // Dragging up-and-left must still produce a top-left-origin rect.
        let rect = AreaSelection.normalize(from: Point(x: 100, y: 100), to: Point(x: 40, y: 60))
        XCTAssertEqual(rect.origin, Point(x: 40, y: 60))
        XCTAssertEqual(rect.size, Size(width: 60, height: 40))
    }

    func testNormalizeEnforcesMinimumSize() {
        let rect = AreaSelection.normalize(from: Point(x: 10, y: 10), to: Point(x: 12, y: 11))
        XCTAssertGreaterThanOrEqual(rect.size.width, AreaSelection.minimumSize.width)
        XCTAssertGreaterThanOrEqual(rect.size.height, AreaSelection.minimumSize.height)
    }

    func testIsValidRejectsTaps() {
        XCTAssertFalse(AreaSelection.isValid(Rect(x: 0, y: 0, width: 5, height: 5)))
        XCTAssertTrue(AreaSelection.isValid(Rect(x: 0, y: 0, width: 100, height: 100)))
    }
}

final class CanvasHitTesterTests: XCTestCase {
    private func makeBlock(_ id: UUID = UUID(), x: Double, y: Double, w: Double, h: Double, z: Int) -> CanvasBlock {
        CanvasBlock(
            recordId: UUID(),
            kind: .text,
            frame: Rect(x: x, y: y, width: w, height: h),
            zIndex: z,
            timestamp: Date(),
            payload: .text(TextBlockPayload(text: ""))
        )
    }

    func testTopBlockIsHighestZIndexUnderPoint() {
        let lower = makeBlock(x: 0, y: 0, w: 100, h: 100, z: 1)
        let upper = makeBlock(x: 10, y: 10, w: 100, h: 100, z: 5)
        let hit = CanvasHitTester.topBlock(at: Point(x: 50, y: 50), in: [lower, upper])
        XCTAssertEqual(hit?.id, upper.id)
    }

    func testTopBlockMissReturnsNil() {
        let block = makeBlock(x: 0, y: 0, w: 10, h: 10, z: 1)
        XCTAssertNil(CanvasHitTester.topBlock(at: Point(x: 500, y: 500), in: [block]))
    }

    func testHitSlopGrowsSmallFrames() {
        let block = makeBlock(x: 0, y: 0, w: 5, h: 5, z: 1)
        // 6pt outside the frame but inside the 8pt slop.
        let hit = CanvasHitTester.topBlock(at: Point(x: 12, y: 12), in: [block])
        XCTAssertEqual(hit?.id, block.id)
    }

    func testBlocksIntersectingMarqueeSortedByZIndex() {
        let a = makeBlock(x: 0, y: 0, w: 50, h: 50, z: 1)
        let b = makeBlock(x: 10, y: 10, w: 50, h: 50, z: 3)
        let c = makeBlock(x: 200, y: 200, w: 50, h: 50, z: 2)
        let hits = CanvasHitTester.blocks(intersecting: Rect(x: 0, y: 0, width: 100, height: 100), in: [a, b, c])
        XCTAssertEqual(hits.map(\.id), [a.id, b.id])
    }

    func testRectIntersects() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(a.intersects(Rect(x: 5, y: 5, width: 10, height: 10)))
        XCTAssertTrue(a.intersects(Rect(x: 9, y: 0, width: 1, height: 1)))
        XCTAssertFalse(a.intersects(Rect(x: 10, y: 0, width: 1, height: 1)))
        XCTAssertFalse(a.intersects(Rect(x: 0, y: 10, width: 1, height: 1)))
    }
}

final class TextBlockLayoutTests: XCTestCase {
    func testClampedFontSize() {
        XCTAssertEqual(TextBlockLayout.clampedFontSize(4), TextBlockLayout.minFontSize)
        XCTAssertEqual(TextBlockLayout.clampedFontSize(100), TextBlockLayout.maxFontSize)
        XCTAssertEqual(TextBlockLayout.clampedFontSize(17), 17)
    }

    func testLineCountWrapsLongText() {
        let count = TextBlockLayout.lineCount(text: String(repeating: "a", count: 200), frameWidth: 100, fontSize: 17)
        XCTAssertGreaterThan(count, 1)
    }

    func testLineCountCountsNewlines() {
        XCTAssertEqual(TextBlockLayout.lineCount(text: "a\nb\nc", frameWidth: 1000, fontSize: 17), 3)
    }

    func testAutoFrameGrowsWithText() {
        let small = TextBlockLayout.autoFrame(marquee: Rect(x: 10, y: 10, width: 200, height: 40), fontSize: 17, text: "hi")
        let tall = TextBlockLayout.autoFrame(marquee: Rect(x: 10, y: 10, width: 200, height: 40), fontSize: 17, text: String(repeating: "word ", count: 100))
        XCTAssertGreaterThan(tall.size.height, small.size.height)
        XCTAssertEqual(tall.minX, 10)
        XCTAssertEqual(tall.minY, 10)
    }

    func testAutoFrameFloorsNarrowSelection() {
        let frame = TextBlockLayout.autoFrame(marquee: Rect(x: 0, y: 0, width: 10, height: 10), fontSize: 17, text: "")
        XCTAssertGreaterThanOrEqual(frame.size.width, 60)
        XCTAssertGreaterThanOrEqual(frame.size.height, 10)
    }
}

final class BlobNamingTests: XCTestCase {
    func testImageRefLivesUnderMediaIMG() {
        let ref = BlobNaming.imageRef()
        XCTAssertTrue(ref.hasPrefix("Media/IMG/"))
        XCTAssertTrue(ref.hasSuffix(".jpg"))
    }

    func testPdfThumbRefDerivesFromPdfRef() {
        let pdfRef = "Media/PDF/ABC.pdf"
        XCTAssertEqual(BlobNaming.pdfThumbRef(for: pdfRef), "Media/PDF/ABC-thumb.png")
    }

    func testIsMediaRef() {
        XCTAssertTrue(BlobNaming.isMediaRef("Media/IMG/x.jpg"))
        XCTAssertFalse(BlobNaming.isMediaRef("other.jpg"))
    }

    func testRefsAreRelativePaths() {
        XCTAssertFalse(BlobNaming.imageRef().hasPrefix("/"))
        XCTAssertFalse(BlobNaming.pdfRef().hasPrefix("/"))
    }
}
