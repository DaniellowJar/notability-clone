import Foundation
import XCTest
@testable import NotabilityCore

final class InitialRecordTests: XCTestCase {
    func testCreateNotebookWithInitialRecord() throws {
        let store = try NotabilityStore()
        let (notebook, record) = try store.createNotebookWithInitialRecord(title: "Math", coverColorHex: "#FF6600")
        XCTAssertEqual(notebook.title, "Math")
        XCTAssertEqual(record.notebookId, notebook.id)
        XCTAssertEqual(record.title, "Untitled")

        let recs = try store.records(in: notebook.id)
        XCTAssertEqual(recs.map(\.id), [record.id])
    }

    func testAllRecordsStillRequireANotebook() throws {
        let store = try NotabilityStore()
        XCTAssertThrowsError(try store.createRecord(in: UUID(), title: "orphan"))
    }
}

final class BackupTests: XCTestCase {
    private func sampleStore() throws -> NotabilityStore {
        let store = try NotabilityStore()
        let (nb, rec) = try store.createNotebookWithInitialRecord(title: "Math", coverColorHex: "#FF6600")
        try store.renameRecord(rec.id, title: "Lesson 1")
        _ = try store.addBlock(in: rec.id, kind: .text, frame: Rect(x: 1, y: 2, width: 3, height: 4), payload: .text(TextBlockPayload(text: "hello", fontSize: 19, colorHex: "#000000", bold: false)))
        _ = try store.addBlock(in: rec.id, kind: .stroke, frame: Rect(x: 5, y: 5, width: 5, height: 5), payload: .stroke([], recognizedText: "x", corrected: true))
        try store.setAudioTrack(AudioTrack(fileRef: "audio-1.m4a", duration: 91.5), for: rec.id)
        try store.appendTranscriptSegment(TranscriptSegment(recordId: rec.id, seq: 1, text: "first", startTime: 0, endTime: 2))
        try store.appendTranscriptSegment(TranscriptSegment(recordId: rec.id, seq: 2, text: "second", startTime: 2, endTime: 5))
        return store
    }

    func testBackupRoundTrip() throws {
        let source = try sampleStore()
        let data = try source.backupData()

        let target = try NotabilityStore()
        let summary = try target.importBackup(data)
        XCTAssertEqual(summary.total, 7, "1 notebook + 1 record + 2 blocks + 1 audio + 2 segments")

        XCTAssertEqual(try target.allNotebooks().count, 1)
        let nb = try target.allNotebooks()[0]
        let recs = try target.records(in: nb.id)
        XCTAssertEqual(recs.first?.title, "Lesson 1")
        XCTAssertEqual(try target.blocks(in: recs[0].id).map(\.zIndex), [1, 2])
        XCTAssertEqual(try target.audioTrack(for: recs[0].id)?.fileRef, "audio-1.m4a")
        XCTAssertEqual(try target.transcript(for: recs[0].id).segments.map(\.text), ["first", "second"])
    }

    func testExportMatchesSourceBytes() throws {
        let source = try sampleStore()
        let a = try source.backupData()
        let b = try source.backupData()
        XCTAssertEqual(a, b)
    }

    func testImportIsIdempotent() throws {
        let data = try sampleStore().backupData()
        let store = try NotabilityStore()
        _ = try store.importBackup(data)
        let second = try store.importBackup(data)
        XCTAssertEqual(second.total, 0, "re-import inserts nothing")

        let nb = try store.allNotebooks()[0]
        let rec = try store.records(in: nb.id)[0]
        XCTAssertEqual(try store.blocks(in: rec.id).count, 2)
    }

    func testImportRejectsOrphanRecord() throws {
        let data = try sampleStore().backupData()
        var backup = try JSONDecoder().decode(StoreBackup.self, from: data)
        let orphan = Record(notebookId: UUID(), title: "lost")
        backup.records.append(orphan)
        let bad = try JSONEncoder().encode(backup)

        let store = try NotabilityStore()
        XCTAssertThrowsError(try store.importBackup(bad)) { error in
            guard case BackupError.orphanRecord(let id) = error else {
                return XCTFail("expected orphanRecord, got \(error)")
            }
            XCTAssertEqual(id, orphan.id)
        }
    }

    func testImportRejectsUnsupportedVersion() throws {
        let data = try sampleStore().backupData()
        var backup = try JSONDecoder().decode(StoreBackup.self, from: data)
        backup.version = 99
        let bad = try JSONEncoder().encode(backup)
        XCTAssertThrowsError(try NotabilityStore().importBackup(bad)) { error in
            guard case BackupError.unsupportedVersion(let v) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(v, 99)
        }
    }
}