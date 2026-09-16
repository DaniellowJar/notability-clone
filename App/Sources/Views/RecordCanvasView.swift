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
    @State private var recordingSession: RecordingSession?
    @State private var showTranscript = false
    @State private var showQuiz = false

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
            .coordinateSpace(.named("canvas"))
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .bottomBar)
        .overlay(alignment: .top) {
            CanvasToolbarView(
                session: session,
                isRecording: recordingSession?.isRecording ?? false,
                onToggleRecord: { toggleRecording() },
                onShowTranscript: { showTranscript = true },
                onShowQuiz: { showQuiz = true },
                onExtractPDF: { extractPDF(blockID: $0) },
                onRemoveBackground: { removeBackground(blockID: $0) }
            )
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
        .sheet(isPresented: $showTranscript) {
            TranscriptSheet(store: app.store, recordID: record.id, blocks: session.blocks)
        }
        .sheet(isPresented: $showQuiz) {
            QuizSheet(store: app.store, recordID: record.id)
        }
        .onAppear {
            session.load(recordID: record.id, store: app.store)
            let service = StrokeRecognitionService(store: app.store, recordID: record.id, inkStore: inkStore)
            recognitionService = service
            service.schedule()
        }
        .onDisappear {
            session.flushPendingSaves()
            recognitionService = nil
            recordingSession?.stop()
            recordingSession = nil
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

    // MARK: - Audio / transcript / PDF / quiz actions

    private func toggleRecording() {
        let session = recordingSession ?? RecordingSession(store: app.store, recordID: record.id)
        if recordingSession == nil { recordingSession = session }
        if session.isRecording {
            session.stop()
        } else {
            session.start()
        }
    }

    private func extractPDF(blockID: UUID) {
        guard let block = self.session.blocks.first(where: { $0.id == blockID }),
              let ref = block.pdfSourceRef else { return }
        let url = BlobStore.shared.url(for: ref)
        if let extracted = PDFExtractService.extractPage(pdfURL: url) {
            self.session.insertImageFromExtract(extracted, near: blockID)
        } else {
            self.session.errorMessage = "Could not extract the PDF page."
        }
    }

    private func removeBackground(blockID: UUID) {
        guard let block = session.blocks.first(where: { $0.id == blockID }),
              let ref = block.imageRef,
              let data = BlobStore.shared.data(for: ref) else { return }
        Task {
            // TODO(provider): stub returns the image unchanged; the live
            // endpoint returns a transparent PNG once configured (Settings).
            if let out = try? await AppProviders.shared.backgroundRemoval.removeBackground(imagePNG: data) {
                let base = URL(fileURLWithPath: ref).deletingPathExtension().lastPathComponent
                let newRef = "\(BlobNaming.imagesDir)/\(base)-nobg.png"
                if (try? BlobStore.shared.save(out, as: newRef)) != nil {
                    await MainActor.run {
                        session.replaceImageRef(blockID, ref: newRef, backgroundRemoved: true)
                    }
                }
            }
        }
    }
}

private struct PKCanvasContainer: UIViewControllerRepresentable {
    let recordID: UUID
    let store: NotabilityStore
    let inkStore: InkStrokeStore
    /// Called after new strokes are captured & persisted (recognition trigger).
    let onStrokeCaptured: () -> Void
    /// (visibleStrokes, savedStrokes) reported from the coordinator.
    let onStateChange: (Int, Int) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController {
        let controller = CanvasViewController(recordID: recordID, store: store, inkStore: inkStore)
        controller.coordinator.onStateChange = onStateChange
        controller.coordinator.onStrokeCaptured = onStrokeCaptured
        return controller
    }

    func updateUIViewController(_ uiViewController: CanvasViewController, context: Context) {
        uiViewController.coordinator.onStateChange = onStateChange
        uiViewController.coordinator.onStrokeCaptured = onStrokeCaptured
    }
}

/// Hosts the capture PKCanvasView. `viewDidAppear` re-reads the store so the
/// renderer/debug state is correct every time the screen is entered (SwiftUI
/// can reuse a representable's view without re-running make*).
final class CanvasViewController: UIViewController {
    let coordinator = Coordinator()
    private let recordID: UUID
    private let store: NotabilityStore
    private let inkStore: InkStrokeStore

    init(recordID: UUID, store: NotabilityStore, inkStore: InkStrokeStore) {
        self.recordID = recordID
        self.store = store
        self.inkStore = inkStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var canvas: PKCanvasView { view as! PKCanvasView }

    override func loadView() {
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
        canvas.delegate = coordinator
        canvas.onPencilFirstUse = { [weak canvas] in
            let lock = CanvasInputPolicy.shouldLockTouch(afterPencilUse: settings.allowFingerDrawing)
            settings.touchLockedByPencil = lock
            if lock { canvas?.drawingPolicy = .pencilOnly }
        }
        view = canvas
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        coordinator.loadDrawing(into: canvas, store: store, recordID: recordID, inkStore: inkStore)
        coordinator.attach(to: canvas)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        coordinator.reloadFromStore()
    }

    /// Capture coordinator: renders the FULL live drawing (including the
    /// in-progress stroke, so ink appears while you paint) and persists each
    /// stroke as a `.stroke` block when it completes. Native ink is hidden
    /// beneath the opaque ink view, so this is the single source of truth.
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStateChange: ((Int, Int) -> Void)?
        var onStrokeCaptured: (() -> Void)?

        private var picker: PKToolPicker?
        private weak var canvas: PKCanvasView?
        private var recordID: UUID?
        private var store: NotabilityStore?
        private var inkStore: InkStrokeStore?
        /// Strokes persisted as `.stroke` blocks (only completed strokes).
        private var persistedCount = 0
        /// Strokes currently rendered (mirrors the live PKCanvasView drawing).
        private var rendered: [StrokeData] = []
        private var renderedCount = 0

        func loadDrawing(into canvas: PKCanvasView, store: NotabilityStore, recordID: UUID, inkStore: InkStrokeStore) {
            self.canvas = canvas
            self.store = store
            self.recordID = recordID
            self.inkStore = inkStore

            DrawingMigrator.migrateIfNeeded(recordID: recordID, store: store)
            reloadFromStore()
        }

        /// Re-reads stroke blocks from the store and reconciles the ink store,
        /// the hidden canvas drawing, and the reported counts. Safe on every
        /// appear: during active drawing the persisted count matches the store.
        func reloadFromStore() {
            guard let store, let recordID, let canvas else { return }
            let strokeBlocks = (try? store.strokeBlocks(in: recordID)) ?? []
            let strokes = strokeBlocks.compactMap { block -> StrokeData? in
                guard case .stroke(let list, _, _) = block.payload, let first = list.first else { return nil }
                return first
            }
            if strokes.count != persistedCount {
                rendered = strokes
                renderedCount = strokes.count
                persistedCount = strokes.count
                inkStore?.load(strokes)
                canvas.drawing = PKStrokeConverter.drawing(from: strokes)
            }
            onStateChange?(canvas.drawing.strokes.count, persistedCount)
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

        /// Fires continuously while drawing: keep the rendered set in sync with
        /// the live drawing (the in-progress stroke included) so the user sees
        /// ink while they paint. Persistence happens on stroke completion.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let all = canvasView.drawing.strokes
            updateRendered(from: all)
            if all.count < persistedCount {
                removeLastStrokeBlocks(persistedCount - all.count)
                persistedCount = all.count
            }
            onStateChange?(all.count, persistedCount)
        }

        /// The user lifted the tool: the in-progress stroke is now final —
        /// persist any strokes beyond what we've already stored.
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            persistCompleted(from: canvasView.drawing.strokes)
        }

        private func updateRendered(from all: [PKStroke]) {
            guard let inkStore else { return }
            if all.count > renderedCount {
                let new = all[renderedCount...].map(PKStrokeConverter.strokeData)
                rendered.append(contentsOf: new)
                renderedCount = all.count
            } else if all.count < renderedCount {
                rendered = Array(rendered.prefix(all.count))
                renderedCount = all.count
            } else if !all.isEmpty {
                // Same count but the last stroke is in progress — re-render it.
                rendered[all.count - 1] = PKStrokeConverter.strokeData(all[all.count - 1])
            }
            inkStore.load(rendered)
        }

        private func persistCompleted(from all: [PKStroke]) {
            guard let store, let recordID else { return }
            guard all.count > persistedCount else { return }
            let newStrokes = all[persistedCount...].map(PKStrokeConverter.strokeData)
            persist(added: newStrokes)
            persistedCount = all.count
            onStrokeCaptured?()
            onStateChange?(all.count, persistedCount)
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
