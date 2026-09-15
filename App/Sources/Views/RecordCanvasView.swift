import NotabilityCore
import PencilKit
import SwiftUI

/// Phase 1 bare canvas: a plain PKCanvasView with the tool picker and
/// drawing enabled, but no custom rendering or persistence yet.
/// Phase 3 replaces this with a capture-only subclass + custom renderer.
struct RecordCanvasView: View {
    let record: Record

    var body: some View {
        PKCanvasContainer()
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(record.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .bottomBar)
    }
}

private struct PKCanvasContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .systemBackground
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        canvas.accessibilityIdentifier = "canvas"
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}