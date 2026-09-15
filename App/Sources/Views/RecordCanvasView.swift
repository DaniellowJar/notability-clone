import NotabilityCore
import PencilKit
import SwiftUI

/// Phase 1 bare canvas: a plain PKCanvasView with the tool picker and drawing
/// enabled. Strokes are persisted per-record as a `PKDrawing` blob so they
/// survive leaving the screen / app relaunch.
/// Phase 3 replaces this with a capture-only subclass + custom renderer.
struct RecordCanvasView: View {
    let record: Record

    @Environment(AppStore.self) private var app
    @State private var visibleStrokes = 0
    @State private var savedStrokes = -1

    var body: some View {
        PKCanvasContainer(
            recordID: record.id,
            store: app.store,
            onStateChange: { strokes, saved in
                visibleStrokes = strokes
                savedStrokes = saved
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .bottomBar)
        #if DEBUG
        .safeAreaInset(edge: .top) {
            Text("strokes=\(visibleStrokes) saved=\(savedStrokes)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("canvasDebug")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        #endif
    }
}

private struct PKCanvasContainer: UIViewRepresentable {
    let recordID: UUID
    let store: NotabilityStore
    /// (visibleStrokes, savedStrokes) reported from the coordinator.
    let onStateChange: (Int, Int) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let settings = AppSettings.shared
        let canvas = CaptureCanvasView()
        canvas.backgroundColor = .systemBackground
        // Touch paints until the first Pencil scribble locks it off (unless the
        // user explicitly enabled finger painting — then it stays on).
        canvas.drawingPolicy = CanvasInputPolicy.touchAllowedOnOpen(
            allowFingerDrawing: settings.allowFingerDrawing,
            touchLockedByPencil: settings.touchLockedByPencil
        ) ? .anyInput : .pencilOnly
        canvas.tool = PKInkingTool(.pen, color: .label, width: 3)
        canvas.accessibilityIdentifier = "canvas"
        canvas.delegate = context.coordinator
        canvas.onPencilFirstUse = { [weak canvas] in
            let lock = CanvasInputPolicy.shouldLockTouch(afterPencilUse: settings.allowFingerDrawing)
            settings.touchLockedByPencil = lock
            if lock { canvas?.drawingPolicy = .pencilOnly }
        }
        context.coordinator.onStateChange = onStateChange
        context.coordinator.loadDrawing(into: canvas, store: store, recordID: recordID)
        context.coordinator.attach(to: canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onStateChange = onStateChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the shared `PKToolPicker`, loads the persisted drawing on entry,
    /// and writes `drawing.dataRepresentation()` back to the store as the user
    /// draws. Saving is debounced for continuous strokes and flushed whenever
    /// the user lifts the tool.
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStateChange: ((Int, Int) -> Void)?

        private var picker: PKToolPicker?
        private weak var canvas: PKCanvasView?
        private var recordID: UUID?
        private var store: NotabilityStore?
        private var saveWorkItem: DispatchWorkItem?
        private var lastSavedStrokeCount = -1

        func loadDrawing(into canvas: PKCanvasView, store: NotabilityStore, recordID: UUID) {
            self.canvas = canvas
            self.store = store
            self.recordID = recordID

            if let data = try? store.drawingData(for: recordID),
               let drawing = try? PKDrawing(data: data) {
                canvas.drawing = drawing
                lastSavedStrokeCount = drawing.strokes.count
            } else {
                lastSavedStrokeCount = 0
            }
            onStateChange?(canvas.drawing.strokes.count, lastSavedStrokeCount)
        }

        func attach(to canvas: PKCanvasView) {
            let picker = PKToolPicker()
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            self.picker = picker
            DispatchQueue.main.async {
                canvas.becomeFirstResponder()
                picker.setVisible(true, forFirstResponder: canvas)
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let count = canvasView.drawing.strokes.count
            onStateChange?(count, lastSavedStrokeCount)
            scheduleSave(for: canvasView.drawing)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            saveNow(for: canvasView.drawing)
        }

        private func scheduleSave(for drawing: PKDrawing) {
            saveWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.saveNow(for: drawing) }
            saveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }

        private func saveNow(for drawing: PKDrawing) {
            saveWorkItem?.cancel()
            guard let recordID, let store else { return }
            do {
                try store.saveDrawingData(drawing.dataRepresentation(), for: recordID)
                lastSavedStrokeCount = drawing.strokes.count
                onStateChange?(drawing.strokes.count, lastSavedStrokeCount)
            } catch {
                // Leave lastSavedStrokeCount unchanged so the debug label stays honest.
            }
        }
    }
}

/// PKCanvasView subclass that detects the first Apple Pencil touch so the
/// canvas can switch from `.anyInput` to `.pencilOnly` (touch painting off).
/// Phase 3 grows this into the capture-only canvas the custom renderer reads.
private final class CaptureCanvasView: PKCanvasView {
    var onPencilFirstUse: (() -> Void)?
    private var pencilSeen = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard !pencilSeen, touches.contains(where: { $0.type == .pencil }) else { return }
        pencilSeen = true
        onPencilFirstUse?()
    }
}
