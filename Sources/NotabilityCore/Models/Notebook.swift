import Foundation

/// Top-level container. A Notebook holds an ordered list of Records
/// (Record replaces the "Page" concept of Notability).
public struct Notebook: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var coverColorHex: String
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        coverColorHex: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.coverColorHex = coverColorHex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}

/// A Record is a flexible, vertically-infinite canvas (not a fixed page).
public struct Record: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var notebookId: UUID
    public var title: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// Page background pattern. Defaults to plain so pre-texture backups
    /// (which lack the key) still decode.
    public var texture: PageTexture

    public init(
        id: UUID = UUID(),
        notebookId: UUID,
        title: String,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        texture: PageTexture = .plain
    ) {
        self.id = id
        self.notebookId = notebookId
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.texture = texture
    }

    private enum CodingKeys: String, CodingKey {
        case id, notebookId, title, createdAt, modifiedAt, texture
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        notebookId = try c.decode(UUID.self, forKey: .notebookId)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        texture = (try? c.decodeIfPresent(PageTexture.self, forKey: .texture)) ?? .plain
    }
}

/// Audio recording attached to a Record (spec §7).
public struct AudioTrack: Codable, Equatable, Sendable {
    public var fileRef: String
    public var duration: TimeInterval
    /// Wall-clock start of the recording — the origin of the shared
    /// transcript↔canvas clock. nil for legacy/imported tracks (Phase 9 sync
    /// then can't map, which callers handle gracefully).
    public var recordedAt: Date?

    public init(fileRef: String, duration: TimeInterval, recordedAt: Date? = nil) {
        self.fileRef = fileRef
        self.duration = duration
        self.recordedAt = recordedAt
    }
}

/// One transcribed utterance with its time window on the shared clock.
public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var recordId: UUID
    /// Stable ordering position within the transcript.
    public var seq: Int
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval

    public init(
        id: UUID = UUID(),
        recordId: UUID,
        seq: Int,
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.recordId = recordId
        self.seq = seq
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// The full transcript of a Record's audio: ordered segments.
public struct Transcript: Codable, Equatable, Sendable {
    public var segments: [TranscriptSegment]

    public init(segments: [TranscriptSegment]) {
        self.segments = segments
    }

    /// Segments whose window overlaps `time`.
    public func segments(overlapping time: TimeInterval) -> [TranscriptSegment] {
        segments.filter { $0.startTime <= time && time <= $0.endTime }
    }
}