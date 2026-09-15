import Foundation

/// What the canvas is doing right now. Only one layer participates in
/// hit-testing at a time so ink capture, block gestures, and the
/// selection/placement overlay never fight over a touch.
public enum CanvasMode: Equatable, Sendable {
    case draw
    case areaSelect(SelectionIntent)
    case tapToPlace(PlacementIntent)
    case editingBlock(UUID)
}

public enum SelectionIntent: Equatable, Sendable {
    /// Marquee creates a new (empty, focused) text block.
    case newTextBlock
    /// Marquee/tap selects existing block(s) by z-order.
    case selectBlocks
}

public enum PlacementIntent: Equatable, Sendable {
    case image
    case pdf
}

extension CanvasMode {
    public var allowsInkHitTesting: Bool {
        if case .draw = self { true } else { false }
    }

    public var allowsBlockHitTesting: Bool {
        if case .editingBlock = self { true } else { false }
    }

    public var captureOverlayActive: Bool {
        !allowsInkHitTesting
    }

    public var editingBlockID: UUID? {
        if case .editingBlock(let id) = self { id } else { nil }
    }

    public var placementIntent: PlacementIntent? {
        if case .tapToPlace(let intent) = self { intent } else { nil }
    }
}
