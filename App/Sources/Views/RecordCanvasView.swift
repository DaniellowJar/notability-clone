import NotabilityCore
import PencilKit
import SwiftUI

/// Phase 3 canvas: PKCanvasView is the input-capture layer only. Completed
/// strokes are converted to `StrokeData`, persisted as `.stroke` blocks, and
/// drawn by the custom renderer on an opaque ink view that hides the canvas's
/// own ink. Blocks (text/image/PDF) overlay the ink; a `CanvasMode` routes
/// touches so ink, blocks, and the selection/placement overlay never fight.
struct RecordCanvasView: View {
    let record: Record

    @Environment(AppStore.self) private var app
    @State private var visibleStrokes = 0
    @State private var savedStrokes = -1
    @State private var session = CanvasSessionState()
    @State private var inkStore = InkStrokeStore()
    @State private var recognitionService: StrokeRecognitionService?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PKCanvasContainer(
                    recordID: record.id,
                    store: app.store,
                    inkStore: inkStore,
                    onStrokeCaptured: { recognitionService?.schedule() },
                    onStateChange: { strokes, saved in
                        visibleStrokes = strokes
                        savedStrokes = saved
                    }
                )
                .allowsHitTesting(session.mode.allowsInkHitTesting)

                InkRenderView(strokes: inkStore.strokes, style: session.letterMode ? .letterMode : .normal)
                    .allowsHitTesting(false)

                captureOverlay

                CanvasBlockLayer(session: session)
                    .allowsHitTesting(session.mode.allowsBlockHitTesting)
            }
            .overlay(alignment: .bottomTrailing) {
                if session.letterMode {
                    LetterModeIndicatorView(strokes: inkStore.strokes, canvasWidth: proxy.size.width)
                        .allowsHitTesting(false)
                }
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
            let service = StrokeRecognitionService(store: app.store, recordID: record.id, inkStore: inkStore)
            recognitionService = service
            service.schedule()
        }
        .onDisappear {
            session.flushPendingSaves()
            recognitionService = nil
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
    let inkStore: InkStrokeStore
    /// Called after new strokes are captured & persisted (recognition trigger).
    let onStrokeCaptured: () -> Void
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
        context.coordinator.onStrokeCaptured = onStrokeCaptured
        context.coordinator.loadDrawing(into: canvas, store: store, recordID: recordID, inkStore: inkStore)
        context.coordinator.attach(to: canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onStateChange = onStateChange
        context.coordinator.onStrokeCaptured = onStrokeCaptured
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Capture coordinator: migrates any legacy drawing blob, loads existing
    /// stroke blocks as the renderer baseline, diffs newly completed strokes,
    /// and persists each as a `.stroke` block. Native ink is hidden beneath the
    /// opaque ink view, so this is the single source of truth for the renderer.
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStateChange: ((Int, Int) -> Void)?
        var onStrokeCaptured: (() -> Void)?

        private var picker: PKToolPicker?
        private weak var canvas: PKCanvasView?
        private var recordID: UUID?
        private var store: NotabilityStore?
        private var inkStore: InkStrokeStore?
        private var capturedCount = 0

        func loadDrawing(into canvas: PKCanvasView, store: NotabilityStore, recordID: UUID, inkStore: InkStrokeStore) {
            self.canvas = canvas
            self.store = store
            self.recordID = recordID
            self.inkStore = inkStore

            DrawingMigrator.migrateIfNeeded(recordID: recordID, store: store)

            let strokeBlocks = (try? store.strokeBlocks(in: recordID)) ?? []
            let strokes = strokeBlocks.compactMap { block -> StrokeData? in
                guard case .stroke(let list, _, _) = block.payload, let first = list.first else { return nil }
                return first
            }
            inkStore.load(strokes)
            capturedCount = strokes.count
            // Rebuild the canvas's own drawing so its stroke count matches our
            // capture (baseline for diff + undo). Hidden beneath the ink view.
            canvas.drawing = PKStrokeConverter.drawing(from: strokes)
            onStateChange?(canvas.drawing.strokes.count, capturedCount)
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
            guard let inkStore else { return }
            let all = canvasView.drawing.strokes
            if all.count > capturedCount {
                let newStrokes = all[capturedCount...].map(PKStrokeConverter.strokeData)
                inkStore.append(newStrokes)
                persist(added: newStrokes)
                capturedCount = all.count
                onStrokeCaptured?()
            } else if all.count < capturedCount {
                let removedCount = capturedCount - all.count
                inkStore.truncate(to: all.count)
                removeLastStrokeBlocks(removedCount)
                capturedCount = all.count
            }
            onStateChange?(all.count, capturedCount)
        }

        private func persist(added strokes: [StrokeData]) {
            guard let store, let recordID else { return }
            for stroke in strokes {
                do {
                    try store.addBlock(
                        in: recordID, kind: .stroke,
                        frame: stroke.bounds,
                        payload: .stroke([stroke], recognizedText: "", corrected: false)
                    )
                } catch {
                    // Keep the ink in the renderer even if a write fails.
                }
            }
        }

        private func removeLastStrokeBlocks(_ count: Int) {
            guard let store, let recordID, count > 0 else { return }
            let strokeBlocks = (try? store.strokeBlocks(in: recordID)) ?? []
            for block in strokeBlocks.suffix(count) {
                try? store.deleteBlock(block.id)
            }
        }
    }
}

/// PKCanvasView subclass that detects the first Apple Pencil touch so the
/// canvas can switch from `.anyInput` to `.pencilOnly` (touch painting off).
/// Phase 3 uses it as the capture-only canvas.
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
