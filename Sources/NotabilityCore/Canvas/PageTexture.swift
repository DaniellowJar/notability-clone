import Foundation

/// Page background pattern, chosen per page. Rendered in canvas coordinates
/// so it scales crisply with zoom (vector lines/dots, never a bitmap).
public enum PageTexture: String, Codable, CaseIterable, Sendable {
    case plain
    case dots
    case dashedGrid
    case squares
    case hexagons
    case ruledLines

    /// Pattern tile size in canvas points.
    public var tile: Double {
        switch self {
        case .plain: return 0
        case .dots: return 24
        case .dashedGrid: return 28
        case .squares: return 32
        case .hexagons: return 32
        case .ruledLines: return 28
        }
    }

    /// Whole tiles fitting across `size` (columns, rows) — lets the renderer
    /// draw exactly the visible pattern without overdraw math of its own.
    public func columnsAndRows(for size: Size) -> (columns: Int, rows: Int) {
        guard tile > 0, size.width > 0, size.height > 0 else { return (0, 0) }
        return (Int(size.width / tile), Int(size.height / tile))
    }

    public var title: String {
        switch self {
        case .plain: return "Plain"
        case .dots: return "Dots"
        case .dashedGrid: return "Dashed grid"
        case .squares: return "Squares"
        case .hexagons: return "Hexagons"
        case .ruledLines: return "Ruled lines"
        }
    }
}
