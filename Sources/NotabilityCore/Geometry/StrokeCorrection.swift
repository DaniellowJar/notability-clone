import Foundation

/// Handwriting "beautify v1" — geometric correction only (no font morphing,
/// which stays out of scope research). Corrects the dominant visual defects:
/// a leaning letter's slant (shear around its baseline) and a stroke's
/// baseline position. Per-letter baseline regression over a whole text line is
/// a noted follow-up within this phase; v1 anchors each stroke to its own
/// bottom (the handwriting baseline) which already reads cleanly.

/// Estimates the average slant of near-vertical stroke segments.
/// 0 = upright; positive = the top of the stroke leans right (italic).
public enum SlantEstimator {
    public static func estimate(_ points: [StrokePoint]) -> Double {
        var angles: [Double] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.location.x - a.location.x
            let dy = b.location.y - a.location.y
            // Near-vertical segments only: horizontal runs tell us nothing.
            if abs(dy) > 1e-6, abs(dx) < abs(dy) {
                // Going down the stroke, top-right lean gives dx < 0; flip so a
                // right-leaning stroke reads as a positive slant.
                angles.append(atan2(-dx, abs(dy)))
            }
        }
        guard !angles.isEmpty else { return 0 }
        let sorted = angles.sorted()
        return sorted[sorted.count / 2]
    }
}

/// Applies the geometric correction to a single stroke.
public enum StrokeCorrection {
    /// `correctedPoints` = de-slanted (and optionally baseline-snapped) points.
    /// `transform` records what was applied for inspection/reversal.
    ///
    /// - Parameters:
    ///   - targetSlant: desired slant in radians (0 = upright).
    ///   - referenceBaselineY: where the stroke's bottom should sit; nil keeps
    ///     the stroke where it is.
    public static func correct(
        _ stroke: StrokeData,
        targetSlant: Double = 0,
        referenceBaselineY: Double? = nil
    ) -> StrokeData {
        let points = stroke.points
        guard points.count >= 2 else { return stroke }

        let slant = SlantEstimator.estimate(points)
        let shearAngle = slant - targetSlant
        let shear = tan(shearAngle)
        let bottomY = points.map { $0.location.y }.max() ?? 0
        let baselineY = referenceBaselineY ?? bottomY
        let baselineShift = baselineY - bottomY

        var corrected: [StrokePoint] = []
        corrected.reserveCapacity(points.count)
        for point in points {
            var q = point
            q.location.x += (q.location.y - bottomY) * shear
            q.location.y += baselineShift
            corrected.append(q)
        }

        var result = stroke
        result.correctedPoints = corrected
        result.transform = StrokeTransform(
            slant: shearAngle,
            baselineAdjustment: baselineShift,
            xHeightScale: 1
        )
        return result
    }

    /// Shorthand: does the stroke already carry corrected points?
    public static func isCorrected(_ stroke: StrokeData) -> Bool {
        stroke.correctedPoints != nil
    }
}
