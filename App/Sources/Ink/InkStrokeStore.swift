import NotabilityCore
import Observation

/// Live captured ink for one Record, shared between the PKCanvasView
/// coordinator (writer) and the SwiftUI ink render layer (reader).
@Observable
final class InkStrokeStore {
    private(set) var strokes: [StrokeData] = []
    var count: Int { strokes.count }

    func load(_ strokes: [StrokeData]) {
        self.strokes = strokes
    }

    func append(_ new: [StrokeData]) {
        strokes.append(contentsOf: new)
    }

    func truncate(to count: Int) {
        if count < strokes.count {
            strokes = Array(strokes.prefix(count))
        }
    }

    /// Ephemeral in-progress stroke (touch-tracked preview). Rendered on top
    /// at full color; never persisted — the completed stroke replaces it.
    var liveStroke: StrokeData?

    func setLiveStroke(_ stroke: StrokeData) {
        liveStroke = stroke
    }

    func clearLiveStroke() {
        liveStroke = nil
    }
}
