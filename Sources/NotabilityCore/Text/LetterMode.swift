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

    /// Estimated height (canvas points) of a naturally written letter: users
    /// draw letters at a roughly constant *screen* size, which maps to
    /// `screenHeight / scale` canvas points at the current zoom.
    public static func naturalWritingHeight(screenHeight: Double, scale: Double) -> Double {
        guard scale > 0.01 else { return screenHeight }
        return screenHeight / scale
    }

    /// Default horizontal gap (canvas points) joining strokes into one letter.
    public static let letterGap = 8.0

    /// Target glyph height (12px bbox height in page points at 100% zoom).
    public static let targetGlyphHeight = 12.0

    /// Horizontal space (fraction of glyph height) between committed segments.
    /// Proportional so it scales with the glyph, never a fixed point value.
    public static let wordGapFraction = 0.4

    /// Vertical pitch (fraction of glyph height) added below a committed line's
    /// baseline before the next line starts — descender space + interline room.
    public static let lineGapFraction = 1.2

    public static func wordGap(targetHeight: Double = targetGlyphHeight) -> Double {
        targetHeight * wordGapFraction
    }

    public static func lineGap(targetHeight: Double = targetGlyphHeight) -> Double {
        targetHeight * lineGapFraction
    }

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

    /// Union bounds of a cluster.
    public static func clusterBounds(_ cluster: [StrokeData]) -> Rect? {
        cluster.first.map { first in cluster.dropFirst().reduce(first.bounds) { Rect.union($0, $1.bounds) } }
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1
            ? sorted[mid]
            : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Clusters that are diacritics, not letters: much smaller (and higher)
    /// than the typical cluster of the same line — i/j dots, Š, ż, umlauts
    /// written as their own stroke group. Judged only when the line has at
    /// least two clusters of comparable normal letters; a lone small cluster
    /// can't be told apart from a small letter and is treated as a letter.
    public static func diacriticIndices(bounds: [Rect]) -> Set<Int> {
        guard bounds.count >= 2 else { return [] }
        let heights = bounds.map(\.size.height)
        let medianHeight = median(heights)
        guard medianHeight > 0 else { return [] }
        // Reference top: the upper half of normal clusters — diacritics sit
        // above the letters' tops. Use the min (a dot is above everything).
        let top = bounds.map(\.minY).min() ?? 0
        var result: Set<Int> = []
        for (i, b) in bounds.enumerated() {
            let small = b.size.height <= 0.45 * medianHeight
            let high = b.minY <= top + 0.15 * medianHeight
            if small && high { result.insert(i) }
        }
        return result
    }

    /// Line metrics on raw stroke bounds: top of the letter bodies, baseline
    /// (the lowest common letter bottom — descenders j, g, q hang below it and
    /// so don't drag the estimate), and the normalize scale for the
    /// top-to-baseline band targeting `targetHeight`.
    /// Returns nil when there are no letters to measure.
    public static func lineMetrics(
        clusters: [[StrokeData]],
        diacritics: Set<Int>,
        targetHeight: Double = targetGlyphHeight
    ) -> (top: Double, baseline: Double, scale: Double)? {
        var solid: [Rect] = []
        for (i, cluster) in clusters.enumerated() where !diacritics.contains(i) {
            guard let b = clusterBounds(cluster) else { continue }
            solid.append(b)
        }
        guard !solid.isEmpty else { return nil }
        // Baseline = the *shallowest* letter bottom (min maxY): every body
        // letter sits on the baseline while descenders (j, g, q) push BELOW
        // it with a larger maxY — a median would be dragged down by a single
        // descender on a short line.
        let top = solid.map(\.minY).min() ?? 0
        let baseline = solid.map(\.maxY).min() ?? 0
        let height = baseline - top
        guard height >= 2 else { return nil }
        let scale = targetHeight / height
        return (top, baseline, scale)
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
