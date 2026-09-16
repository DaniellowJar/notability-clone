import NotabilityCore
import SwiftUI

/// The SwiftUI overlay that renders record blocks at their absolute positions
/// on top of the ink canvas, plus the mode-specific capture overlays that route
/// touches during area-selection / tap-to-place / editing.
struct CanvasBlockLayer: View {
    @Bindable var session: CanvasSessionState

    var body: some View {
        ForEach(session.blocks) { block in
            CanvasBlockView(
                session: session,
                block: block,
                isSelected: session.mode.editingBlockID == block.id
            )
            .position(x: block.frame.center.x, y: block.frame.center.y)
        }
    }
}

private struct CanvasBlockView: View {
    @Bindable var session: CanvasSessionState
    let block: CanvasBlock
    let isSelected: Bool
    @State private var lastDragLocation: CGPoint?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Button {
                        session.deleteBlock(block.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.red)
                            .background(Circle().fill(.background))
                    }
                    .frame(width: 44, height: 44)
                    .offset(x: 22, y: -22)
                    .accessibilityIdentifier("blockDelete")
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-6)
                }
            }
            .gesture(moveGesture)
            .onTapGesture { session.selectBlock(block.id) }
    }

    @ViewBuilder
    private var content: some View {
        switch block.payload {
        case .text:
            TextBlockView(session: session, block: block, isSelected: isSelected)
        case .image:
            ImageBlockView(block: block)
        case .pdfPage:
            PDFBlockView(block: block, zoomScale: session.transform.scale)
        case .calc:
            CalcBlockView(session: session, block: block)
        default:
            EmptyView()
        }
    }

    private var moveGesture: some Gesture {
        // Use location deltas in a fixed named space ("canvas"): a DragGesture's
        // `translation` double-counts when the dragged view itself moves under
        // the finger, which made blocks jitter back and forth.
        DragGesture(minimumDistance: 10, coordinateSpace: .named("canvas"))
            .onChanged { value in
                guard isSelected else { return }
                if lastDragLocation == nil { lastDragLocation = value.location }
                guard let last = lastDragLocation else { return }
                let dx = value.location.x - last.x
                let dy = value.location.y - last.y
                lastDragLocation = value.location
                let current = block.frame.origin
                session.moveBlock(
                    id: block.id,
                    to: Point(x: max(0, current.x + dx), y: max(0, current.y + dy))
                )
            }
            .onEnded { _ in
                lastDragLocation = nil
                session.finishMoveBlock(id: block.id)
            }
    }
}

// MARK: - Capture overlays

/// Drag-to-select overlay used by the Text (new text block) and Select tools.
struct MarqueeOverlay: View {
    @Bindable var session: CanvasSessionState
    let intent: SelectionIntent

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        session.beginOrUpdateMarquee(at: Point(x: value.location.x, y: value.location.y))
                    }
                    .onEnded { _ in
                        session.endAreaSelect(intent: intent)
                    }
            )
            .overlay(alignment: .topLeading) {
                if let marquee = session.marquee {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 1)
                        .background(Color.accentColor.opacity(0.15))
                        .frame(width: marquee.size.width, height: marquee.size.height)
                        .position(x: marquee.center.x, y: marquee.center.y)
                }
            }
    }
}

/// Tap-to-place overlay used by the Image and PDF tools.
struct PlaceOverlay: View {
    @Bindable var session: CanvasSessionState
    let intent: PlacementIntent

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    session.place(intent: intent, at: Point(x: value.location.x, y: value.location.y))
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 160, height: 120)
                    .padding(12)
            }
    }
}

/// Tap-empty-space-to-deselect overlay used while editing a block.
struct DeselectOverlay: View {
    @Bindable var session: CanvasSessionState

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(TapGesture().onEnded { session.deselect() })
    }
}

// MARK: - Helpers

extension View {
    /// Reports the view's intrinsic size (after layout) through `onChange`.
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size) }
                    .onChange(of: proxy.size) { _, size in onChange(size) }
            }
        )
    }
}
