import Foundation

/// Pure hit-testing over block frames: topmost zIndex first, with a touch
/// slop so small blocks are still easy to grab on iPad.
public enum CanvasHitTester {
    /// Points of extra reach added around a block frame before hit-testing.
    public static let hitSlop: Double = 8

    /// The topmost block (highest zIndex) whose (slop-inflated) frame contains
    /// `point`. nil when no block is under the point.
    public static func topBlock(
        at point: Point,
        in blocks: [CanvasBlock],
        hitSlop: Double = CanvasHitTester.hitSlop
    ) -> CanvasBlock? {
        blocks
            .filter { inset($0.frame, by: hitSlop).contains(point) }
            .max { $0.zIndex < $1.zIndex }
    }

    /// Blocks whose frames intersect `rect`, lowest zIndex first. Used by the
    /// selection marquee. `hitSlop` is subtracted (not added) so the marquee
    /// must meaningfully overlap a block to select it.
    public static func blocks(
        intersecting rect: Rect,
        in blocks: [CanvasBlock],
        hitSlop: Double = 0
    ) -> [CanvasBlock] {
        blocks
            .filter { $0.frame.intersects(inset(rect, by: -hitSlop)) }
            .sorted { $0.zIndex < $1.zIndex }
    }

    private static func inset(_ rect: Rect, by amount: Double) -> Rect {
        Rect(
            x: rect.minX - amount,
            y: rect.minY - amount,
            width: rect.size.width + amount * 2,
            height: rect.size.height + amount * 2
        )
    }
}
