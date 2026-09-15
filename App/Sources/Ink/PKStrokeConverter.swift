import NotabilityCore
import PencilKit

/// Lossy-but-faithful conversion between PencilKit strokes and the core
/// `StrokeData` model. Used to (a) capture ink from the PKCanvasView and
/// (b) rebuild the PKCanvasView's drawing on open so undo/diff stay consistent.
enum PKStrokeConverter {
    static func strokeData(from stroke: PKStroke) -> StrokeData {
        // PKStrokePath is a Collection of PKStrokePoint — read the control
        // points directly (no interpolation strategy to depend on).
        let samples = Array(stroke.path)
        let points = samples.map { sample in
            StrokePoint(
                location: Point(x: Double(sample.location.x), y: Double(sample.location.y)),
                timestampOffset: sample.timeOffset,
                width: Double(sample.size.width),
                force: sample.force,
                azimuth: sample.azimuth,
                altitude: sample.altitude
            )
        }
        let ci = stroke.ink.color
        let color = UIColor(
            red: CGFloat(ci.red), green: CGFloat(ci.green),
            blue: CGFloat(ci.blue), alpha: CGFloat(ci.alpha)
        )
        let baseWidth = Double(samples.map { $0.size.width }.max() ?? 3)
        return StrokeData(points: points, colorHex: color.hexString, baseWidth: baseWidth)
    }

    static func stroke(from data: StrokeData) -> PKStroke {
        var samples = data.points.map { point in
            PKStrokePoint(
                location: CGPoint(x: point.location.x, y: point.location.y),
                timeOffset: point.timestampOffset,
                size: CGSize(width: point.width, height: point.width),
                opacity: 1,
                force: point.force,
                azimuth: point.azimuth,
                altitude: point.altitude
            )
        }
        if samples.isEmpty {
            samples = [PKStrokePoint(
                location: .zero, timeOffset: 0,
                size: CGSize(width: 2, height: 2), opacity: 1,
                force: 1, azimuth: 0, altitude: 90
            )]
        }
        let path = PKStrokePath(controlPoints: samples, creationDate: Date())
        let ink = PKInk(.pen, color: UIColor(hex: data.colorHex), width: CGFloat(data.baseWidth))
        return PKStroke(ink: ink, path: path)
    }

    static func drawing(from strokes: [StrokeData]) -> PKDrawing {
        PKDrawing(strokes: strokes.map(stroke(from:)))
    }
}
