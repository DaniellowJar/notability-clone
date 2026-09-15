import XCTest
import NotabilityCore
@testable import NotabilityClone

final class BlobStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> BlobStore { BlobStore(root: root) }

    func testSaveAndLoadRoundTrip() throws {
        let store = makeStore()
        let ref = BlobNaming.imageRef()
        let data = Data([0, 1, 2, 3])
        try store.save(data, as: ref)
        XCTAssertEqual(store.data(for: ref), data)
        XCTAssertTrue(store.exists(ref))
        XCTAssertTrue(store.url(for: ref).path.hasPrefix(root.path))
    }

    func testDeleteRemovesBlob() throws {
        let store = makeStore()
        let ref = BlobNaming.imageRef()
        try store.save(Data([1]), as: ref)
        store.delete(ref)
        XCTAssertFalse(store.exists(ref))
    }

    func testDeleteIfUnreferencedKeepsReferencedBlobs() throws {
        let store = makeStore()
        let ref = BlobNaming.imageRef()
        try store.save(Data([1]), as: ref)
        let block = CanvasBlock(
            recordId: UUID(), kind: .image,
            frame: .zero, zIndex: 1, timestamp: Date(),
            payload: .image(ImageBlockPayload(imageRef: ref))
        )
        store.deleteIfUnreferenced(refs: [ref], among: [block])
        XCTAssertTrue(store.exists(ref))
    }

    func testDeleteIfUnreferencedRemovesOrphanedBlob() throws {
        let store = makeStore()
        let ref = BlobNaming.imageRef()
        try store.save(Data([1]), as: ref)
        store.deleteIfUnreferenced(refs: [ref], among: [])
        XCTAssertFalse(store.exists(ref))
    }
}

final class CanvasSessionTests: XCTestCase {
    private var store: NotabilityStore!
    private var recordID: UUID!

    override func setUpWithError() throws {
        store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        recordID = try store.createRecord(in: nb.id, title: "r").id
    }

    func testMarqueeCreatesTextBlockAndSelectsIt() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)

        session.startTextTool()
        session.beginOrUpdateMarquee(at: Point(x: 20, y: 20))
        session.beginOrUpdateMarquee(at: Point(x: 220, y: 100))
        session.endAreaSelect(intent: .newTextBlock)

        XCTAssertEqual(session.blocks.count, 1)
        guard case .text(let payload) = session.blocks[0].payload else {
            return XCTFail("expected text block")
        }
        XCTAssertEqual(payload.fontSize, TextBlockLayout.defaultFontSize)
        XCTAssertEqual(session.mode.editingBlockID, session.blocks[0].id)
    }

    func testTextEditsPersistAfterFlush() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startTextTool()
        session.beginOrUpdateMarquee(at: Point(x: 0, y: 0))
        session.beginOrUpdateMarquee(at: Point(x: 200, y: 80))
        session.endAreaSelect(intent: .newTextBlock)

        let id = session.blocks[0].id
        session.setText(id, text: "hello world")
        session.setTextFontSize(id, size: 24)
        session.flushPendingSaves()

        let reloaded = CanvasSessionState()
        reloaded.load(recordID: recordID, store: store)
        XCTAssertEqual(reloaded.blocks.count, 1)
        guard case .text(let payload) = reloaded.blocks[0].payload else {
            return XCTFail("expected text block")
        }
        XCTAssertEqual(payload.text, "hello world")
        XCTAssertEqual(payload.fontSize, 24)
    }

    func testTapToPlaceInsertsImageBlock() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startPlaceImage(ref: "Media/IMG/fixture.jpg")
        session.place(intent: .image, at: Point(x: 300, y: 300))

        XCTAssertEqual(session.blocks.count, 1)
        guard case .image = session.blocks[0].payload else {
            return XCTFail("expected image block")
        }
        XCTAssertEqual(session.mode, .draw, "placement returns to draw mode")
    }

    func testDeleteBlockRemovesRow() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startTextTool()
        session.beginOrUpdateMarquee(at: Point(x: 0, y: 0))
        session.beginOrUpdateMarquee(at: Point(x: 100, y: 100))
        session.endAreaSelect(intent: .newTextBlock)
        let id = session.blocks[0].id

        session.deleteBlock(id)
        XCTAssertTrue(session.blocks.isEmpty)
        XCTAssertTrue(try store.blocks(in: recordID).isEmpty)
    }

    func testFontSizeIsClamped() {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startTextTool()
        session.beginOrUpdateMarquee(at: Point(x: 0, y: 0))
        session.beginOrUpdateMarquee(at: Point(x: 100, y: 100))
        session.endAreaSelect(intent: .newTextBlock)
        let id = session.blocks[0].id

        session.setTextFontSize(id, size: 200)
        XCTAssertEqual(session.blocks[0].textPayload?.fontSize, TextBlockLayout.maxFontSize)
    }
}
