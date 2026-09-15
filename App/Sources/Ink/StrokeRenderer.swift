import CoreGraphics
import NotabilityCore
import UIKit

/// Draws captured strokes into a CGContext. Behind a protocol so Phase 5
/// (corrected points) and Phase 6 (Letter Mode fading) can swap renderers.
protocol StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext)
}

/// Polyline renderer: per-stroke color + uniform base width, using corrected
/// points when present (Phase 5 hook), else raw capture points.
struct CoreGraphicsStrokeRenderer: StrokeRendering {
    func draw(_ strokes: [StrokeData], in context: CGContext) {
        for stroke in strokes {
            let points = stroke.correctedPoints ?? stroke.points
            guard let first = points.first else { continue }
            context.saveGState()
            context.setStrokeColor(UIColor(hex: stroke.colorHex).cgColor)
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
}
