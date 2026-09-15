import Foundation

/// The live set of captured strokes for one Record, as the app sees them.
/// The PKCanvasView stays the capture layer; every completed stroke is
/// converted to `StrokeData` and tracked here (and persisted as `.stroke`
/// blocks). Undo shrinks the count → `truncate(to:)`.
public struct StrokeCollection: Equatable, Sendable {
    public private(set) var strokes: [StrokeData]

    public init(strokes: [StrokeData] = []) {
        self.strokes = strokes
    }

    public var count: Int { strokes.count }
    public var isEmpty: Bool { strokes.isEmpty }

    /// Union of all stroke bounds; `.zero` when empty.
    public var bounds: Rect {
        guard let first = strokes.first else { return .zero }
        return strokes.dropFirst().reduce(first.bounds) { Rect.union($0, $1.bounds) }
    }

    public mutating func append(_ stroke: StrokeData) {
        strokes.append(stroke)
    }

    public mutating func append(contentsOf newStrokes: [StrokeData]) {
        strokes.append(contentsOf: newStrokes)
    }

    /// Drop strokes beyond `count` (e.g. after an undo) — returns the removed.
    @discardableResult
    public mutating func truncate(to count: Int) -> [StrokeData] {
        guard count >= 0, count < strokes.count else { return [] }
        let removed = Array(strokes.dropFirst(count))
        strokes = Array(strokes.prefix(count))
        return removed
    }

    /// Reconciles this collection with an externally observed stroke count:
    /// returns strokes that need persisting (new) or deleting (removed).
    public mutating func reconcile(observedCount: Int, newStrokes: [StrokeData]) -> Reconciliation {
        if observedCount > count {
            let added = newStrokes
            append(contentsOf: added)
            return .added(added)
        } else if observedCount < count {
            let removed = truncate(to: observedCount)
            return .removed(removed)
        }
        return .none
    }

    public enum Reconciliation: Equatable {
        case none
        case added([StrokeData])
        case removed([StrokeData])
    }
}
