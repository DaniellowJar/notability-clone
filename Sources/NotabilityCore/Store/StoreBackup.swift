import Foundation

/// JSON exchange format for the whole store.
///
/// Two consumers:
/// - LiveContainer seeding: drop `notability-seed.json` into the app's
///   Documents folder and the store is populated on next launch.
/// - The WebDAV sync layer (phase 11) diff/merges at block level; this
///   envelope is the "full snapshot" primitive those block diffs derive from.
public struct StoreBackup: Codable, Equatable, Sendable {
    public var version: Int
    public var notebooks: [Notebook]
    public var records: [Record]
    public var blocks: [CanvasBlock]
    public var audioTracks: [AudioTrackBackup]
    public var transcriptSegments: [TranscriptSegment]

    public init(
        notebooks: [Notebook],
        records: [Record],
        blocks: [CanvasBlock],
        audioTracks: [AudioTrackBackup],
        transcriptSegments: [TranscriptSegment],
        version: Int = 1
    ) {
        self.version = version
        self.notebooks = notebooks
        self.records = records
        self.blocks = blocks
        self.audioTracks = audioTracks
        self.transcriptSegments = transcriptSegments
    }
}

/// An audio track as stored: the track itself does not know its record.
public struct AudioTrackBackup: Codable, Equatable, Sendable {
    public var recordId: UUID
    public var track: AudioTrack

    public init(recordId: UUID, track: AudioTrack) {
        self.recordId = recordId
        self.track = track
    }
}

/// Counts of rows inserted by an import (skips any that already exist, so
/// importing is idempotent).
public struct BackupSummary: Equatable, Sendable {
    public var notebooks: Int
    public var records: Int
    public var blocks: Int
    public var audioTracks: Int
    public var transcriptSegments: Int

    public init(
        notebooks: Int,
        records: Int,
        blocks: Int,
        audioTracks: Int,
        transcriptSegments: Int
    ) {
        self.notebooks = notebooks
        self.records = records
        self.blocks = blocks
        self.audioTracks = audioTracks
        self.transcriptSegments = transcriptSegments
    }

    public var total: Int {
        notebooks + records + blocks + audioTracks + transcriptSegments
    }
}

public enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case duplicateNotebookID
    case duplicateRecordID
    case orphanRecord(UUID)
    case orphanBlock(UUID)
    case orphanAudioTrack(UUID)
    case orphanTranscriptSegment(UUID)
}