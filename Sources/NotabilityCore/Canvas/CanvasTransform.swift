import Foundation

/// Maps between canvas points (the stored coordinate space: blocks, strokes,
/// marquee) and screen points (what the user sees and touches).
/// screen = canvas * scale + offset. Pure and Linux-testable; the app layer
/// applies this to rendering and inverse-maps every gesture through it.
public struct CanvasTransform: Codable, Equatable, Sendable {
    /// Pinching out back to the original size floors here — never below 1.0.
    public static let minScale = 1.0
    public static let maxScale = 4.0
    /// Pinching out snaps exactly to 1.0 when this close to it.
    public static let snapThreshold = 0.05

    public var scale: Double
    public var offsetX: Double
    public var offsetY: Double

    public init(scale: Double = 1.0, offsetX: Double = 0, offsetY: Double = 0) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public static let identity = CanvasTransform()

    public func toScreen(_ p: Point) -> Point {
        Point(x: p.x * scale + offsetX, y: p.y * scale + offsetY)
    }

    public func toCanvas(_ p: Point) -> Point {
        guard scale != 0 else { return p }
        return Point(x: (p.x - offsetX) / scale, y: (p.y - offsetY) / scale)
    }

    public func toScreen(_ r: Rect) -> Rect {
        let origin = toScreen(r.origin)
        return Rect(x: origin.x, y: origin.y, width: r.size.width * scale, height: r.size.height * scale)
    }

    public func toCanvas(_ r: Rect) -> Rect {
        let origin = toCanvas(r.origin)
        guard scale != 0 else { return r }
        return Rect(x: origin.x, y: origin.y, width: r.size.width / scale, height: r.size.height / scale)
    }

    /// Clamp a proposed scale into range, snapping to 1.0 near the floor so
    /// "pinch out until original size" lands exactly.
    public static func clampedScale(_ scale: Double) -> Double {
        if scale < minScale + snapThreshold { return minScale }
        return min(max(scale, minScale), maxScale)
    }

    /// Zoom keeping the screen anchor point stable (pinch-around-finger).
    public func zoomed(to newScale: Double, anchorScreen anchor: Point) -> CanvasTransform {
        let s = Self.clampedScale(newScale)
        guard scale != 0 else { return CanvasTransform(scale: s, offsetX: anchor.x, offsetY: anchor.y) }
        let k = s / scale
        return CanvasTransform(
            scale: s,
            offsetX: anchor.x - (anchor.x - offsetX) * k,
            offsetY: anchor.y - (anchor.y - offsetY) * k
        )
    }

    /// One Maps-style frame: zoom about the moving anchor, then translate.
    /// Applied from the CURRENT transform on every event — never recomputed
    /// from a gesture-start base, which is what keeps simultaneous zoom+drag
    /// smooth instead of jumpy.
    public func zoomPanStep(scaleRatio: Double, anchorScreen: Point, pan: Point) -> CanvasTransform {
        zoomed(to: scale * scaleRatio, anchorScreen: anchorScreen).panned(by: pan)
    }

    public func panned(by delta: Point) -> CanvasTransform {
        CanvasTransform(scale: scale, offsetX: offsetX + delta.x, offsetY: offsetY + delta.y)
    }

    /// Backing-store scale for raster views (ink, tiles): display scale times
    /// canvas zoom, so vector content re-rasterizes crisply instead of having
    /// a 1x bitmap magnified. Floored at the display scale itself.
    public static func rasterScale(screenScale: Double, zoom: Double) -> Double {
        max(screenScale, 0.01) * max(zoom, 1)
    }

    /// Canvas-space Y of the viewport's bottom edge for the current transform.
    /// Scrolling down (negative offsetY) pushes it past the content, which is
    /// what makes the page grow ahead of the user instead of only behind ink.
    public static func visibleBottom(viewportHeight: Double, offsetY: Double, scale: Double) -> Double {
        (viewportHeight - offsetY) / max(scale, 0.01)
    }

    /// Infinite-canvas growth rule: content height never shrinks and always
    /// covers the viewport plus padding below the lowest content.
    public static func grownHeight(current: Double, contentBottom: Double, viewportHeight: Double, padding: Double) -> Double {
        max(current, viewportHeight, contentBottom + padding)
    }
}
