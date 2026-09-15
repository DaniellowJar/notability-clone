import Foundation
import GRDB

enum SchemaError: Error, Equatable {
    case notebookMissing(UUID)
    case recordMissing(UUID)
}

/// SQLite schema for NotabilityCore.
///
/// Design notes (justification for GRDB over Core Data, spec §3):
/// - Plain SQLite is byte-identical on iOS and Linux, so the same store the
///   app ships with is what `swift test` runs against on the dev box.
/// - The OwnCloud sync layer (phase 11) does block-level diff/merge against
///   WebDAV; explicit SQLSELECT/INSERT/DELETE map directly onto that work,
///   where Core Data's object graph adds indirection without benefit.
/// - Dates stored as Double (timeIntervalSinceReferenceDate) so ordering and
///   the shared audio<->canvas clock are exact and queryable without NSPredicate.
enum DatastoreSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            // Foreign keys must be enabled before any table is touched.
            try db.execute(sql: "PRAGMA foreign_keys = ON;")

            try db.execute(sql: """
                CREATE TABLE notebook (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    coverColorHex TEXT NOT NULL,
                    createdAt DOUBLE NOT NULL,
                    modifiedAt DOUBLE NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE record (
                    id TEXT PRIMARY KEY NOT NULL,
                    notebookId TEXT NOT NULL REFERENCES notebook(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    createdAt DOUBLE NOT NULL,
                    modifiedAt DOUBLE NOT NULL
                );
                CREATE INDEX idx_record_notebook ON record(notebookId);
                """)

            try db.execute(sql: """
                CREATE TABLE canvasBlock (
                    id TEXT PRIMARY KEY NOT NULL,
                    recordId TEXT NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    frameX DOUBLE NOT NULL,
                    frameY DOUBLE NOT NULL,
                    frameWidth DOUBLE NOT NULL,
                    frameHeight DOUBLE NOT NULL,
                    zIndex INTEGER NOT NULL,
                    timestamp DOUBLE NOT NULL,
                    payload TEXT NOT NULL,
                    modifiedAt DOUBLE NOT NULL
                );
                CREATE INDEX idx_block_record ON canvasBlock(recordId);
                CREATE INDEX idx_block_z ON canvasBlock(recordId, zIndex);
                CREATE INDEX idx_block_timestamp ON canvasBlock(recordId, timestamp);
                """)

            try db.execute(sql: """
                CREATE TABLE audioTrack (
                    recordId TEXT PRIMARY KEY NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    fileRef TEXT NOT NULL,
                    duration DOUBLE NOT NULL
                );
                """)

            try db.execute(sql: """
                CREATE TABLE transcriptSegment (
                    id TEXT PRIMARY KEY NOT NULL,
                    recordId TEXT NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    seq INTEGER NOT NULL,
                    text TEXT NOT NULL,
                    startTime DOUBLE NOT NULL,
                    endTime DOUBLE NOT NULL
                );
                CREATE INDEX idx_segment_record ON transcriptSegment(recordId, seq);
                """)
        }

        // Bare-canvas persistence: the record's PencilKit drawing blob
        // (`PKDrawing.dataRepresentation()`). Phase 3 replaces this with
        // per-stroke canvasBlock storage.
        migrator.registerMigration("v2_record_drawing") { db in
            try db.execute(sql: "ALTER TABLE record ADD COLUMN drawingData BLOB")
        }

        return migrator
    }
}