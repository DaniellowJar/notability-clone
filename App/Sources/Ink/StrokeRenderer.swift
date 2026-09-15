import CoreGraphics
import NotabilityCore
import UIKit

/// Draws captured strokes into a CGContext. Behind a protocol so Phase 5
/// (corrected points) and Phase 6 (Letter Mode aging) can swap renderers.
protocol StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext)
}

/// Polyline renderer: per-stroke color + uniform base width, using corrected
/// points when present (Phase 5 hook), else raw capture points.
struct CoreGraphicsStrokeRenderer: StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext) {
        for stroke in strokes {
            draw(stroke: stroke, colorHex: stroke.colorHex, alpha: 1, in: context)
        }
    }

    func draw(stroke: StrokeData, colorHex: String, alpha: Double, in context: CGContext) {
        let points = stroke.correctedPoints ?? stroke.points
        guard let first = points.first else { return }
        context.saveGState()
        context.setStrokeColor(UIColor(hex: colorHex).withAlphaComponent(CGFloat(alpha)).cgColor)
        context.setLineWidth(CGFloat(stroke.baseWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: CGPoint(x: first.location.x, y: first.location.y))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: point.location.x, y: point.location.y))
        }
        context.strokePath()
        context.restoreGState()
    }
}

/// Letter Mode renderer: older strokes fade from the user's ink color through
/// mid-gray to light gray by age (newest = full color). Uses the shared
/// per-stroke path drawing so correction still applies.
struct LetterModeStrokeRenderer: StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext) {
        for (index, stroke) in strokes.enumerated() {
            let age = LetterModeAging.ageFraction(strokeIndex: index, total: strokes.count)
            let style = LetterModeAging.style(inkHex: stroke.colorHex, ageFraction: age)
            CoreGraphicsStrokeRenderer().draw(stroke: stroke, colorHex: style.hex, alpha: style.alpha, in: context)
        }
    }
}
