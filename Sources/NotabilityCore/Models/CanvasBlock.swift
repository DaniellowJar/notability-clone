import Foundation

/// A single element on a Record's canvas. Every block carries a creation
/// `timestamp` — the backbone of audio<->canvas sync (spec §3).
public struct CanvasBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var recordId: UUID
    public var kind: CanvasBlockKind
    public var frame: Rect
    public var zIndex: Int
    /// Created at = first stroke point / first keystroke in real time.
    public var timestamp: Date
    public var payload: BlockPayload
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        recordId: UUID,
        kind: CanvasBlockKind,
        frame: Rect,
        zIndex: Int,
        timestamp: Date,
        payload: BlockPayload,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.recordId = recordId
        self.kind = kind
        self.frame = frame
        self.zIndex = zIndex
        self.timestamp = timestamp
        self.payload = payload
        self.modifiedAt = modifiedAt
    }

    /// Convenience factory for creating a new block with "now" timestamps and
    /// an auto z-order supplied by the caller.
    public static func make(
        in recordId: UUID,
        kind: CanvasBlockKind,
        frame: Rect,
        zIndex: Int,
        payload: BlockPayload,
        at timestamp: Date = Date()
    ) -> CanvasBlock {
        CanvasBlock(
            recordId: recordId,
            kind: kind,
            frame: frame,
            zIndex: zIndex,
            timestamp: timestamp,
            payload: payload
        )
    }
}