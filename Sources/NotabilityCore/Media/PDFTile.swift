import Foundation

/// Zoom-dependent raster sizing for vector-backed PDF blocks. PDF pages are
/// resolution-independent, so instead of baking one fixed JPEG we render at
/// exactly the pixels the current zoom needs (bucketed to keep re-renders
/// infrequent, capped to bound memory).
public enum PDFTile {
    /// Longest side cap in pixels — bounds memory for huge blocks at deep zoom.
    public static let maxPixels = 4096.0

    /// Zoom bucketed to 0.5 steps so a continuous pinch doesn't re-render
    /// every frame. Floored at 1 (the transform never goes below 100%).
    public static func zoomBucket(_ zoom: Double) -> Double {
        max(1, ceil(max(zoom, 0) * 2) / 2)
    }

    /// Pixel size for rendering `frame` (canvas points) at `zoom` on a
    /// `displayScale` screen, aspect-preserved under the pixel cap.
    public static func pixelSize(frame: Size, zoomScale: Double, displayScale: Double) -> Size {
        guard frame.width > 0, frame.height > 0, displayScale > 0 else { return .zero }
        let factor = displayScale * zoomBucket(zoomScale)
        var width = frame.width * factor
        var height = frame.height * factor
        let longest = max(width, height)
        if longest > maxPixels {
            let down = maxPixels / longest
            width *= down
            height *= down
        }
        return Size(width: width, height: height)
    }
}
