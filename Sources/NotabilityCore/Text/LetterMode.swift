import Foundation

/// Letter Mode v2 (write-zoom-commit) pure math. The app layer owns the zoom
/// transform, the settle timer, and persistence; this computes fit, follow,
/// normalize, and the trailing-letter window for the aging renderer.
public enum LetterMode {
    /// Scale so a marquee-selected area fills the viewport width. Floored at
    /// 1.0 — an area wider than the screen simply stays at original size,
    /// consistent with the pinch-out-to-100% floor.
    public static func zoomToFit(
        areaWidth: Double,
        viewportWidth: Double,
        maxScale: Double = CanvasTransform.maxScale
    ) -> Double {
        guard areaWidth > 0, viewportWidth > 0 else { return 1 }
        return min(max(viewportWidth / areaWidth, 1), maxScale)
    }

    /// Follow the writing cursor: when the writing position passes `threshold`
    /// of the viewport width, shift the offset so it sits back at threshold —
    /// the camera pans left, leaving fresh space on the right.
    public static func followOffset(
        writingCanvasX: Double,
        scale: Double,
        offsetX: Double,
        viewportWidth: Double,
        threshold: Double = 0.7
    ) -> Double {
        let writingScreenX = writingCanvasX * scale + offsetX
        let limit = threshold * viewportWidth
        guard writingScreenX > limit else { return offsetX }
        return offsetX - (writingScreenX - limit)
    }

    /// Scale factor normalizing a committed line to the target glyph height
    /// (12px bbox height in page points at 100% zoom).
    public static func normalizeScale(lineHeight: Double, targetHeight: Double = 12) -> Double {
        guard lineHeight > 0, targetHeight > 0 else { return 1 }
        return targetHeight / lineHeight
    }

    /// Default horizontal gap (canvas points) joining strokes into one letter.
    public static let letterGap = 8.0

    /// Group strokes into letters by horizontal gap, preserving draw order.
    /// A stroke whose left edge falls within `gap` of the previous cluster's
    /// right edge joins that letter — i-dots and t-crosses land in the
    /// cluster they belong to; anything further starts a new letter.
    public static func letterClusters(strokes: [StrokeData], gap: Double = letterGap) -> [[StrokeData]] {
        var clusters: [[StrokeData]] = []
        var clusterRight: [Double] = []
        for stroke in strokes {
            let b = stroke.bounds
            if let lastRight = clusterRight.last, b.minX - lastRight <= gap {
                clusters[clusters.count - 1].append(stroke)
                clusterRight[clusterRight.count - 1] = max(lastRight, b.maxX)
            } else {
                clusters.append([stroke])
                clusterRight.append(b.maxX)
            }
        }
        return clusters
    }

    /// Alpha for the cluster N positions back from the newest (0 = newest).
    /// Newest in full color, two fading predecessors, older hidden — the
    /// visible trailing window is ~3 letters.
    public static func clusterAlpha(positionsBackFromNewest n: Int) -> Double {
        switch n {
        case 0: return 1.0
        case 1: return 0.55
        case 2: return 0.25
        default: return 0
        }
    }
}
