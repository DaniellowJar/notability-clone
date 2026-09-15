import XCTest
@testable import NotabilityCore

final class TimelineSyncTests: XCTestCase {
    private let recordingStart = Date(timeIntervalSince1970: 1000)

    private func block(timestamp: Date, id: UUID = UUID()) -> CanvasBlock {
        CanvasBlock(id: id, recordId: UUID(), kind: .text, frame: .zero, zIndex: 1,
                    timestamp: timestamp, payload: .text(TextBlockPayload(text: "")))
    }

    func testWallClockMapping() {
        XCTAssertEqual(TimelineSync.wallClock(5, since: recordingStart), Date(timeIntervalSince1970: 1005))
    }

    func testBlocksOverlappingSegment() {
        let inside = block(timestamp: Date(timeIntervalSince1970: 1003))
        let before = block(timestamp: Date(timeIntervalSince1970: 990))
        let after = block(timestamp: Date(timeIntervalSince1970: 1020))
        let hits = TimelineSync.blocks([after, before, inside], overlapping: 0, endOffset: 10, recordingStart: recordingStart)
        XCTAssertEqual(hits.map(\.id), [inside.id])
    }

    func testSegmentsOverlappingTime() {
        let segments = [
            TranscriptSegment(recordId: UUID(), seq: 0, text: "a", startTime: 0, endTime: 2),
            TranscriptSegment(recordId: UUID(), seq: 1, text: "b", startTime: 2, endTime: 5),
        ]
        let hit = TimelineSync.segments(segments, overlapping: Date(timeIntervalSince1970: 1003.5), recordingStart: recordingStart)
        XCTAssertEqual(hit.map(\.text), ["b"])
    }
}

final class SyncDiffEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 100)
    private let t1 = Date(timeIntervalSince1970: 200)

    func testMissingSides() {
        let plan = SyncDiffEngine.plan(
            local: [LocalEntry(path: "a.txt", modifiedAt: t0)],
            remote: [RemoteFile(path: "b.txt", modifiedAt: t0)]
        )
        XCTAssertEqual(plan.ops, [.upload(path: "a.txt"), .download(path: "b.txt")])
    }

    func testLocalNewerUploads() {
        let plan = SyncDiffEngine.plan(
            local: [LocalEntry(path: "x", modifiedAt: t1)],
            remote: [RemoteFile(path: "x", modifiedAt: t0)]
        )
        XCTAssertEqual(plan.ops, [.upload(path: "x")])
    }

    func testRemoteNewerDownloads() {
        let plan = SyncDiffEngine.plan(
            local: [LocalEntry(path: "x", modifiedAt: t0)],
            remote: [RemoteFile(path: "x", modifiedAt: t1)]
        )
        XCTAssertEqual(plan.ops, [.download(path: "x")])
    }

    func testEqualIsNoop() {
        let plan = SyncDiffEngine.plan(
            local: [LocalEntry(path: "x", modifiedAt: t0)],
            remote: [RemoteFile(path: "x", modifiedAt: t0, etag: "abc")]
        )
        XCTAssertTrue(plan.isEmpty)
    }
}
