import NotabilityCore
import PencilKit
import SwiftUI

/// Phase 2 canvas: ink (PKCanvasView) with SwiftUI blocks overlaid, driven by
/// a `CanvasMode`. Strokes persist as a per-record PKDrawing blob; blocks
/// persist as canvasBlock rows. Mode routing guarantees ink, block gestures,
/// and the selection/placement overlay never fight over a touch.
/// Phase 3 replaces the blob ink with a capture-only subclass + custom renderer.
struct RecordCanvasView: View {
    let record: Record

    @Environment(AppStore.self) private var app
    @State private var visibleStrokes = 0
    @State private var savedStrokes = -1
    @State private var session = CanvasSessionState()

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                PKCanvasContainer(
                    recordID: record.id,
                    store: app.store,
                    onStateChange: { strokes, saved in
                        visibleStrokes = strokes
                        savedStrokes = saved
                    }
                )
                .allowsHitTesting(session.mode.allowsInkHitTesting)

                CanvasBlockLayer(session: session)
                    .allowsHitTesting(session.mode.allowsBlockHitTesting)

                captureOverlay
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .bottomBar)
        .overlay(alignment: .top) {
            CanvasToolbarView(session: session)
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text("strokes=\(visibleStrokes) saved=\(savedStrokes) blocks=\(session.blocks.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
                .accessibilityIdentifier("canvasDebug")
                .padding(.horizontal)
                .padding(.top, 52)
        }
        #endif
        .onAppear {
            session.load(recordID: record.id, store: app.store)
        }
        .onDisappear {
            session.flushPendingSaves()
        }
        .alert("Error", isPresented: errorAlertBinding) {
        } message: {
            Text(session.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var captureOverlay: some View {
        switch session.mode {
        case .areaSelect(let intent):
            MarqueeOverlay(session: session, intent: intent)
        case .tapToPlace(let intent):
            PlaceOverlay(session: session, intent: intent)
        case .editingBlock:
            DeselectOverlay(session: session)
        case .draw:
            EmptyView()
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )
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
