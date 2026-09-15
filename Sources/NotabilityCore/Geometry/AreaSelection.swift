import Foundation

/// Normalizes a drag gesture (start → current) into a top-left-origin Rect.
/// Enforces a minimum size so an accidental tap doesn't create a sliver block.
public enum AreaSelection {
    /// Minimum selectable area; anything smaller is dropped by callers.
    public static let minimumSize = Size(width: 32, height: 32)

    public static func normalize(
        from start: Point,
        to end: Point,
        minSize: Size = AreaSelection.minimumSize
    ) -> Rect {
        var rect = Rect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        if rect.size.width < minSize.width { rect.size.width = minSize.width }
        if rect.size.height < minSize.height { rect.size.height = minSize.height }
        return rect
    }

    /// True when the drag is large enough to be a real selection rather than a tap.
    public static func isValid(_ rect: Rect) -> Bool {
        rect.size.width >= minimumSize.width && rect.size.height >= minimumSize.height
    }
}
