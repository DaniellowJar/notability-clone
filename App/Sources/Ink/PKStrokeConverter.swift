import NotabilityCore
import PencilKit
import UIKit

/// Lossy-but-faithful conversion between PencilKit strokes and the core
/// `StrokeData` model. Used to (a) capture ink from the PKCanvasView and
/// (b) rebuild the PKCanvasView's drawing on open so undo/diff stay consistent.
enum PKStrokeConverter {
    /// `traits` must be the capturing canvas's own trait collection: dynamic
    /// ink colors (adding a white `.label` pen in dark mode) only resolve to
    /// their dark appearance under dark traits. The ambient
    /// `UITraitCollection.current` is unreliable between UI hosts, which
    /// persisted e.g. white ink as black and made it invisible forever after.
    static func colorHex(from ink: PKInk, traits: UITraitCollection) -> String {
        ink.color.hexString(resolvedWith: traits)
    }

    static func strokeData(from stroke: PKStroke, traits: UITraitCollection) -> StrokeData {
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
        // iOS 18 SDK: PKInk.color is a UIColor and PKInk has no width property —
        // use the stroke's sampled point widths for the base width instead.
        let baseWidth = Double(samples.map { $0.size.width }.max() ?? 3)
        return StrokeData(points: points, colorHex: colorHex(from: stroke.ink, traits: traits), baseWidth: baseWidth)
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
        let ink = PKInk(.pen, color: UIColor(hex: data.colorHex))
        return PKStroke(ink: ink, path: path)
    }

    static func drawing(from strokes: [StrokeData]) -> PKDrawing {
        PKDrawing(strokes: strokes.map(stroke(from:)))
    }
}
