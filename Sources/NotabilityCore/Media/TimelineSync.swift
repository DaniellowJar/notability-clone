import Foundation

/// Shared-clock mapping between transcript segments and canvas blocks (Phase 9).
/// Blocks carry a wall-clock `timestamp`; transcript segments carry offsets
/// from the recording's start. `recordingStart` links the two.
public enum TimelineSync {
    /// Wall-clock time for a transcript offset.
    public static func wallClock(_ offset: TimeInterval, since start: Date) -> Date {
        start.addingTimeInterval(offset)
    }

    /// Blocks whose creation timestamp falls in the wall-clock window implied by
    /// a transcript segment `[startOffset, endOffset]`. Sorted by timestamp.
    public static func blocks(
        _ blocks: [CanvasBlock],
        overlapping startOffset: TimeInterval,
        endOffset: TimeInterval,
        recordingStart: Date
    ) -> [CanvasBlock] {
        let start = wallClock(startOffset, since: recordingStart)
        let end = wallClock(endOffset, since: recordingStart)
        return blocks
            .filter { $0.timestamp >= start && $0.timestamp <= end }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// The transcript segments whose window overlaps the given canvas time.
    public static func segments<T: Sequence>(
        _ segments: T,
        overlapping time: Date,
        recordingStart: Date
    ) -> [T.Element] where T.Element == TranscriptSegment {
        let offset = time.timeIntervalSince(recordingStart)
        return segments.filter { $0.startTime <= offset && offset <= $0.endTime }
    }
}
