import Foundation
import GRDB

/// GRDB-backed persistence layer. Thread-safe: all access funnels through a
/// single `DatabaseQueue` (or `DatabasePool` if we later need read concurrency).
public final class NotabilityStore: @unchecked Sendable {
    public let writer: DatabaseWriter

    private init(writer: DatabaseWriter) {
        self.writer = writer
    }

    public convenience init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: path, configuration: config)
        try DatastoreSchema.migrator.migrate(queue)
        self.init(writer: queue)
    }

    /// In-memory store for tests and previews.
    public convenience init(inMemory: Bool = true) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try DatastoreSchema.migrator.migrate(queue)
        self.init(writer: queue)
    }

    // MARK: - Notebooks

    public func createNotebook(title: String, coverColorHex: String) throws -> Notebook {
        try writer.write { db in
            let notebook = Notebook(title: title, coverColorHex: coverColorHex)
            try db.execute(
                sql: """
                INSERT INTO notebook (id, title, coverColorHex, createdAt, modifiedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    notebook.id.uuidString,
                    notebook.title,
                    notebook.coverColorHex,
                    notebook.createdAt.timeIntervalSinceReferenceDate,
                    notebook.modifiedAt.timeIntervalSinceReferenceDate
                ]
            )
            return notebook
        }
    }

    public func allNotebooks() throws -> [Notebook] {
        try writer.read { db in
            try Self.fetchNotebooks(db, order: "createdAt")
        }
    }

    public func renameNotebook(_ id: UUID, title: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE notebook SET title = ?, modifiedAt = ? WHERE id = ?",
                arguments: [title, Date().timeIntervalSinceReferenceDate, id.uuidString]
            )
        }
    }

    public func deleteNotebook(_ id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM notebook WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Creates a notebook together with its first (untitled) record, so the
    /// app can drop the user straight onto a canvas right after creating a
    /// notebook (Notability-style) without hitting an empty records screen.
    public func createNotebookWithInitialRecord(
        title: String,
        coverColorHex: String,
        recordTitle: String = "Untitled"
    ) throws -> (notebook: Notebook, record: Record) {
        try writer.write { db in
            let notebook = Notebook(title: title, coverColorHex: coverColorHex)
            try db.execute(
                sql: """
                INSERT INTO notebook (id, title, coverColorHex, createdAt, modifiedAt)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    notebook.id.uuidString,
                    notebook.title,
                    notebook.coverColorHex,
                    notebook.createdAt.timeIntervalSinceReferenceDate,
                    notebook.modifiedAt.timeIntervalSinceReferenceDate
                ]
            )
            let record = Record(notebookId: notebook.id, title: recordTitle)
            try db.execute(
                sql: """
                INSERT INTO record (id, notebookId, title, createdAt, modifiedAt, texture)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.notebookId.uuidString,
                    record.title,
                    record.createdAt.timeIntervalSinceReferenceDate,
                    record.modifiedAt.timeIntervalSinceReferenceDate,
                    record.texture.rawValue
                ]
            )
            return (notebook, record)
        }
    }

    // MARK: - Records

    public func createRecord(in notebookId: UUID, title: String) throws -> Record {
        try writer.write { db in
            guard try db.tableExists("notebook") else { throw SchemaError.notebookMissing(notebookId) }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notebook WHERE id = ?", arguments: [notebookId.uuidString]) ?? 0
            guard count > 0 else { throw SchemaError.notebookMissing(notebookId) }
            let record = Record(notebookId: notebookId, title: title)
            try db.execute(
                sql: """
                INSERT INTO record (id, notebookId, title, createdAt, modifiedAt, texture)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    record.id.uuidString,
                    record.notebookId.uuidString,
                    record.title,
                    record.createdAt.timeIntervalSinceReferenceDate,
                    record.modifiedAt.timeIntervalSinceReferenceDate,
                    record.texture.rawValue
                ]
            )
            return record
        }
    }

    public func records(in notebookId: UUID) throws -> [Record] {
        try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM record WHERE notebookId = ? ORDER BY createdAt",
                arguments: [notebookId.uuidString]
            )
            return rows.map(Self.decodeRecord)
        }
    }

    public func renameRecord(_ id: UUID, title: String) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE record SET title = ?, modifiedAt = ? WHERE id = ?",
                arguments: [title, Date().timeIntervalSinceReferenceDate, id.uuidString]
            )
        }
    }

    public func texture(for recordId: UUID) throws -> PageTexture {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT texture FROM record WHERE id = ?", arguments: [recordId.uuidString]),
                  let raw = row["texture"] as String?,
                  let texture = PageTexture(rawValue: raw) else {
                return .plain
            }
            return texture
        }
    }

    /// Sets a record's background texture (bumps `modifiedAt` so it syncs).
    public func setRecordTexture(_ texture: PageTexture, for recordId: UUID) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE record SET texture = ?, modifiedAt = ? WHERE id = ?",
                arguments: [texture.rawValue, Date().timeIntervalSinceReferenceDate, recordId.uuidString]
            )
        }
    }

    public func deleteRecord(_ id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM record WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Canvas drawing

    /// Persists a record's PencilKit drawing blob (`PKDrawing.dataRepresentation()`)
    /// and bumps `modifiedAt`. The bare PKCanvasView saves here until Phase 3
    /// moves strokes into per-stroke canvasBlock rows.
    public func saveDrawingData(_ data: Data, for recordId: UUID) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE record SET drawingData = ?, modifiedAt = ? WHERE id = ?",
                arguments: [data, Date().timeIntervalSinceReferenceDate, recordId.uuidString]
            )
        }
    }

    public func drawingData(for recordId: UUID) throws -> Data? {
        try writer.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT drawingData FROM record WHERE id = ?",
                arguments: [recordId.uuidString]
            )
        }
    }

    /// Clears a record's legacy drawing blob after it has been migrated to
    /// `.stroke` blocks.
    public func clearDrawingData(for recordId: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "UPDATE record SET drawingData = NULL WHERE id = ?", arguments: [recordId.uuidString])
        }
    }

    /// Latest modification time across the store — the LWW timestamp used when
    /// syncing a whole backup snapshot.
    public func latestModifiedAt() -> Date {
        (try? writer.read { db in
            let raw = try Double.fetchOne(db, sql: """
                SELECT MAX(m) FROM (
                    SELECT MAX(modifiedAt) AS m FROM notebook
                    UNION ALL SELECT MAX(modifiedAt) FROM record
                    UNION ALL SELECT MAX(modifiedAt) FROM canvasBlock
                )
                """)
            return raw.map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date(timeIntervalSinceReferenceDate: 0)
        }) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// `.stroke` blocks in capture order (timestamp then zIndex) — how the
    /// custom renderer reconstructs a record's ink, and how undo truncates.
    public func strokeBlocks(in recordId: UUID) throws -> [CanvasBlock] {
        try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM canvasBlock WHERE recordId = ? AND kind = 'stroke' ORDER BY timestamp, zIndex",
                arguments: [recordId.uuidString]
            )
            return rows.map(Self.decodeBlock)
        }
    }

    // MARK: - Blocks

    public func addBlock(
        in recordId: UUID,
        kind: CanvasBlockKind,
        frame: Rect,
        payload: BlockPayload,
        at timestamp: Date = Date()
    ) throws -> CanvasBlock {
        try writer.write { db in
            guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record WHERE id = ?", arguments: [recordId.uuidString]) ?? 0 > 0 else {
                throw SchemaError.recordMissing(recordId)
            }
            let maxZ = try Int.fetchOne(
                db,
                sql: "SELECT MAX(zIndex) FROM canvasBlock WHERE recordId = ?",
                arguments: [recordId.uuidString]
            ) ?? 0
            let block = CanvasBlock.make(
                in: recordId,
                kind: kind,
                frame: frame,
                zIndex: maxZ + 1,
                payload: payload,
                at: timestamp
            )
            try insertBlock(db, block)
            return block
        }
    }

    public func blocks(in recordId: UUID) throws -> [CanvasBlock] {
        try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM canvasBlock WHERE recordId = ? ORDER BY zIndex",
                arguments: [recordId.uuidString]
            )
            return rows.map(Self.decodeBlock)
        }
    }

    public func block(id: UUID) throws -> CanvasBlock? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM canvasBlock WHERE id = ?", arguments: [id.uuidString]) else {
                return nil
            }
            return Self.decodeBlock(row)
        }
    }

    public func updateBlockFrame(_ id: UUID, frame: Rect) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE canvasBlock SET frameX = ?, frameY = ?, frameWidth = ?, frameHeight = ?, modifiedAt = ? WHERE id = ?",
                arguments: [
                    frame.origin.x, frame.origin.y,
                    frame.size.width, frame.size.height,
                    Date().timeIntervalSinceReferenceDate,
                    id.uuidString
                ]
            )
        }
    }

    public func updateBlockPayload(_ id: UUID, payload: BlockPayload) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE canvasBlock SET payload = ?, modifiedAt = ? WHERE id = ?",
                arguments: [try Self.encode(payload), Date().timeIntervalSinceReferenceDate, id.uuidString]
            )
        }
    }

    public func deleteBlock(_ id: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM canvasBlock WHERE id = ?", arguments: [id.uuidString])
        }
    }

    // MARK: - Audio + transcript

    public func setAudioTrack(_ track: AudioTrack, for recordId: UUID) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO audioTrack (recordId, fileRef, duration, recordedAt) VALUES (?, ?, ?, ?)
                ON CONFLICT(recordId) DO UPDATE SET fileRef = excluded.fileRef, duration = excluded.duration, recordedAt = excluded.recordedAt
                """,
                arguments: [recordId.uuidString, track.fileRef, track.duration, track.recordedAt?.timeIntervalSinceReferenceDate]
            )
        }
    }

    public func audioTrack(for recordId: UUID) throws -> AudioTrack? {
        try writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM audioTrack WHERE recordId = ?", arguments: [recordId.uuidString]) else {
                return nil
            }
            return AudioTrack(
                fileRef: row["fileRef"] as String,
                duration: row["duration"] as Double,
                recordedAt: (row["recordedAt"] as Double?).map(Date.init(timeIntervalSinceReferenceDate:))
            )
        }
    }

    public func appendTranscriptSegment(_ segment: TranscriptSegment) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO transcriptSegment (id, recordId, seq, text, startTime, endTime)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    segment.id.uuidString, segment.recordId.uuidString, segment.seq,
                    segment.text, segment.startTime, segment.endTime
                ]
            )
        }
    }

    public func transcript(for recordId: UUID) throws -> Transcript {
        try writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM transcriptSegment WHERE recordId = ? ORDER BY seq",
                arguments: [recordId.uuidString]
            )
            let segments = rows.map { row in
                TranscriptSegment(
                    id: UUID(uuidString: row["id"] as String)!,
                    recordId: UUID(uuidString: row["recordId"] as String)!,
                    seq: row["seq"] as Int,
                    text: row["text"] as String,
                    startTime: row["startTime"] as Double,
                    endTime: row["endTime"] as Double
                )
            }
            return Transcript(segments: segments)
        }
    }

    public func clearTranscript(for recordId: UUID) throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM transcriptSegment WHERE recordId = ?", arguments: [recordId.uuidString])
        }
    }

    // MARK: - Backup (JSON seed / export)

    /// Full-store snapshot as JSON. Idempotent-importable via `importBackup`.
    public func backupData() throws -> Data {
        try writer.read { db in
            let notebooks = try Self.fetchNotebooks(db, order: "createdAt")

            let records = try Row.fetchAll(db, sql: "SELECT * FROM record ORDER BY createdAt").map(Self.decodeRecord)
            let blocks = try Row.fetchAll(db, sql: "SELECT * FROM canvasBlock ORDER BY recordId, zIndex").map(Self.decodeBlock)

            let audioRows = try Row.fetchAll(db, sql: "SELECT recordId, fileRef, duration FROM audioTrack")
            let audio = audioRows.map { row in
                AudioTrackBackup(
                    recordId: UUID(uuidString: row["recordId"] as String)!,
                    track: AudioTrack(
                        fileRef: row["fileRef"] as String,
                        duration: row["duration"] as Double
                    )
                )
            }

            let segmentRows = try Row.fetchAll(db, sql: "SELECT * FROM transcriptSegment ORDER BY seq")
            let segments = segmentRows.map { row in
                TranscriptSegment(
                    id: UUID(uuidString: row["id"] as String)!,
                    recordId: UUID(uuidString: row["recordId"] as String)!,
                    seq: row["seq"] as Int,
                    text: row["text"] as String,
                    startTime: row["startTime"] as Double,
                    endTime: row["endTime"] as Double
                )
            }

            let backup = StoreBackup(
                notebooks: notebooks,
                records: records,
                blocks: blocks,
                audioTracks: audio,
                transcriptSegments: segments
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(backup)
        }
    }

    /// Imports a `StoreBackup`. Rows whose id already exists are skipped, so
    /// re-importing (e.g. a fixed seed file kept in Documents) never duplicates.
    /// zIndex/seq are recomputed per record so ordering stays consistent even
    /// when the file is stale relative to the current store.
    public func importBackup(_ data: Data) throws -> BackupSummary {
        let backup = try JSONDecoder().decode(StoreBackup.self, from: data)
        guard backup.version == 1 else { throw BackupError.unsupportedVersion(backup.version) }

        guard Set(backup.notebooks.map(\.id)).count == backup.notebooks.count else {
            throw BackupError.duplicateNotebookID
        }
        guard Set(backup.records.map(\.id)).count == backup.records.count else {
            throw BackupError.duplicateRecordID
        }

        let notebookIDs = Set(backup.notebooks.map(\.id))
        let recordIDs = Set(backup.records.map(\.id))
        for record in backup.records where !notebookIDs.contains(record.notebookId) {
            throw BackupError.orphanRecord(record.id)
        }
        for block in backup.blocks where !recordIDs.contains(block.recordId) {
            throw BackupError.orphanBlock(block.id)
        }
        for track in backup.audioTracks where !recordIDs.contains(track.recordId) {
            throw BackupError.orphanAudioTrack(track.recordId)
        }
        for segment in backup.transcriptSegments where !recordIDs.contains(segment.recordId) {
            throw BackupError.orphanTranscriptSegment(segment.id)
        }

        return try writer.write { db in
            var summary = BackupSummary(notebooks: 0, records: 0, blocks: 0, audioTracks: 0, transcriptSegments: 0)

            for notebook in backup.notebooks {
                let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notebook WHERE id = ?", arguments: [notebook.id.uuidString]) ?? 0
                guard exists == 0 else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO notebook (id, title, coverColorHex, createdAt, modifiedAt)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        notebook.id.uuidString, notebook.title, notebook.coverColorHex,
                        notebook.createdAt.timeIntervalSinceReferenceDate,
                        notebook.modifiedAt.timeIntervalSinceReferenceDate
                    ]
                )
                summary.notebooks += 1
            }

            for record in backup.records {
                let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM record WHERE id = ?", arguments: [record.id.uuidString]) ?? 0
                guard exists == 0 else { continue }
                try db.execute(
                    sql: """
                    INSERT INTO record (id, notebookId, title, createdAt, modifiedAt, texture)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        record.id.uuidString, record.notebookId.uuidString, record.title,
                        record.createdAt.timeIntervalSinceReferenceDate,
                        record.modifiedAt.timeIntervalSinceReferenceDate,
                        record.texture.rawValue
                    ]
                )
                summary.records += 1
            }

            // zIndex: append after whatever the store already has per record.
            var nextZ: [UUID: Int] = [:]
            for block in backup.blocks {
                let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM canvasBlock WHERE id = ?", arguments: [block.id.uuidString]) ?? 0
                guard exists == 0 else { continue }
                let z: Int
                if let current = nextZ[block.recordId] {
                    z = current + 1
                } else {
                    let maxZ = try Int.fetchOne(db, sql: "SELECT MAX(zIndex) FROM canvasBlock WHERE recordId = ?", arguments: [block.recordId.uuidString]) ?? 0
                    z = maxZ + 1
                }
                nextZ[block.recordId] = z
                try db.execute(
                    sql: """
                    INSERT INTO canvasBlock (
                        id, recordId, kind, frameX, frameY, frameWidth, frameHeight,
                        zIndex, timestamp, payload, modifiedAt
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        block.id.uuidString, block.recordId.uuidString, block.kind.rawValue,
                        block.frame.origin.x, block.frame.origin.y,
                        block.frame.size.width, block.frame.size.height,
                        z,
                        block.timestamp.timeIntervalSinceReferenceDate,
                        try Self.encode(block.payload),
                        block.modifiedAt.timeIntervalSinceReferenceDate
                    ]
                )
                summary.blocks += 1
            }

            for trackEntry in backup.audioTracks {
                let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM audioTrack WHERE recordId = ?", arguments: [trackEntry.recordId.uuidString]) ?? 0
                guard exists == 0 else { continue }
                try db.execute(
                    sql: "INSERT INTO audioTrack (recordId, fileRef, duration, recordedAt) VALUES (?, ?, ?, ?)",
                    arguments: [trackEntry.recordId.uuidString, trackEntry.track.fileRef, trackEntry.track.duration,
                                trackEntry.track.recordedAt?.timeIntervalSinceReferenceDate]
                )
                summary.audioTracks += 1
            }

            var nextSeq: [UUID: Int] = [:]
            for segment in backup.transcriptSegments {
                let exists = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcriptSegment WHERE id = ?", arguments: [segment.id.uuidString]) ?? 0
                guard exists == 0 else { continue }
                let seq: Int
                if let current = nextSeq[segment.recordId] {
                    seq = current + 1
                } else {
                    let maxSeq = try Int.fetchOne(db, sql: "SELECT MAX(seq) FROM transcriptSegment WHERE recordId = ?", arguments: [segment.recordId.uuidString]) ?? 0
                    seq = maxSeq + 1
                }
                nextSeq[segment.recordId] = seq
                try db.execute(
                    sql: "INSERT INTO transcriptSegment (id, recordId, seq, text, startTime, endTime) VALUES (?, ?, ?, ?, ?, ?)",
                    arguments: [
                        segment.id.uuidString, segment.recordId.uuidString, seq,
                        segment.text, segment.startTime, segment.endTime
                    ]
                )
                summary.transcriptSegments += 1
            }

            return summary
        }
    }

    // MARK: - Private helpers

    private func insertBlock(_ db: Database, _ block: CanvasBlock) throws {
        try db.execute(
            sql: """
            INSERT INTO canvasBlock (
                id, recordId, kind, frameX, frameY, frameWidth, frameHeight,
                zIndex, timestamp, payload, modifiedAt
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                block.id.uuidString,
                block.recordId.uuidString,
                block.kind.rawValue,
                block.frame.origin.x, block.frame.origin.y,
                block.frame.size.width, block.frame.size.height,
                block.zIndex,
                block.timestamp.timeIntervalSinceReferenceDate,
                try Self.encode(block.payload),
                block.modifiedAt.timeIntervalSinceReferenceDate
            ]
        )
    }

    private static func decodeRecord(_ row: Row) -> Record {
        Record(
            id: UUID(uuidString: row["id"] as String)!,
            notebookId: UUID(uuidString: row["notebookId"] as String)!,
            title: row["title"] as String,
            createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"] as Double),
            modifiedAt: Date(timeIntervalSinceReferenceDate: row["modifiedAt"] as Double),
            texture: PageTexture(rawValue: (row["texture"] as String?) ?? "plain") ?? .plain
        )
    }

    private static func decodeBlock(_ row: Row) -> CanvasBlock {
        var rect = Rect.zero
        rect.origin.x = row["frameX"] as Double
        rect.origin.y = row["frameY"] as Double
        rect.size.width = row["frameWidth"] as Double
        rect.size.height = row["frameHeight"] as Double
        return CanvasBlock(
            id: UUID(uuidString: row["id"] as String)!,
            recordId: UUID(uuidString: row["recordId"] as String)!,
            kind: CanvasBlockKind(rawValue: row["kind"] as String) ?? .text,
            frame: rect,
            zIndex: row["zIndex"] as Int,
            timestamp: Date(timeIntervalSinceReferenceDate: row["timestamp"] as Double),
            payload: (try? Self.decode(row["payload"] as String, as: BlockPayload.self)) ?? .text(TextBlockPayload(text: "")),
            modifiedAt: Date(timeIntervalSinceReferenceDate: row["modifiedAt"] as Double)
        )
    }

    private static func fetchNotebooks(_ db: Database, order: String) throws -> [Notebook] {
        let rows = try Row.fetchAll(db, sql: "SELECT * FROM notebook ORDER BY \(order)")
        return rows.map { row in
            Notebook(
                id: UUID(uuidString: row["id"] as String)!,
                title: row["title"] as String,
                coverColorHex: row["coverColorHex"] as String,
                createdAt: Date(timeIntervalSinceReferenceDate: row["createdAt"] as Double),
                modifiedAt: Date(timeIntervalSinceReferenceDate: row["modifiedAt"] as Double)
            )
        }
    }

    private static func encode(_ payload: BlockPayload) throws -> String {
        let data = try JSONEncoder().encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ string: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(string.utf8))
    }
}