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

/// Letter Mode renderer: the trailing ~3 letter clusters fade from the current
/// ink color to grey (newest full color, two fading predecessors, older
/// hidden). Uses the shared per-stroke path drawing so correction still
/// applies. Stored hexes are used as-is — dynamic colors were resolved to
/// concrete RGB at capture, so white stays white until it starts fading.
struct LetterModeStrokeRenderer: StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext) {
        let clusters = LetterMode.letterClusters(strokes: strokes)
        let renderer = CoreGraphicsStrokeRenderer()
        for (ci, cluster) in clusters.enumerated() {
            let alpha = LetterMode.clusterAlpha(positionsBackFromNewest: clusters.count - 1 - ci)
            guard alpha > 0 else { continue }
            for stroke in cluster {
                let hex = LetterModeAging.fadedColor(inkHex: stroke.colorHex, ageFraction: 1 - alpha)
                renderer.draw(stroke: stroke, colorHex: hex, alpha: alpha, in: context)
            }
        }
    }
}
