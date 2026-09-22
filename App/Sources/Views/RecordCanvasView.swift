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
                Color(.systemGroupedBackground)
                // Page container: fixed content size in canvas points, scaled
                // and panned by the session transform. Everything inside uses
                // canvas coordinates; gestures inverse-map through it.
                ZStack(alignment: .topLeading) {
                    PageTextureView(texture: session.pageTexture,
                                    contentWidth: session.contentWidth,
                                    contentHeight: session.contentHeight)
                        .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1 / CGFloat(max(session.transform.scale, 0.01)))
                        .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                    PageHeaderView(record: record, format: session.headerFormat)
                        .frame(width: CGFloat(session.contentWidth), height: PageHeaderView.height)
                    PKCanvasContainer(
                        recordID: record.id,
                        store: app.store,
                        inkStore: inkStore,
                        rewriteToken: session.drawingRewriteToken,
                        onStrokeCaptured: { recognitionService?.schedule() },
                        onStateChange: { strokes, saved in
                            visibleStrokes = strokes
                            savedStrokes = saved
                            growContent()
                            if session.letterArea != nil,
                               let pt = inkStore.strokes.last?.points.last {
                                session.trackLetterWriting(x: pt.location.x, y: pt.location.y)
                            }
                        },
                        onStrokeBegin: { x, y in
                            session.handleLetterStrokeBegin(x: x, y: y)
                        }
                    )
                    .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                    .allowsHitTesting(session.mode.allowsInkHitTesting)
                    InkRenderView(strokes: inkStore.strokes, style: session.letterArea != nil ? .letterMode : .normal, liveStroke: inkStore.liveStroke, zoomScale: session.transform.scale, rewriteToken: session.drawingRewriteToken)
                        .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                        .allowsHitTesting(false)

                    if let area = session.letterArea {
                        // Baseline guide: shows where committed letter bodies
                        // will land; descenders (j, g, q) have room below it.
                        Color.clear
                            .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                            .overlay {
                                LetterBaselineGuide(
                                    area: area,
                                    baselineY: session.letterCursor.y + CanvasSessionState.letterCommittedHeight,
                                    scale: session.transform.scale
                                )
                            }
                            .allowsHitTesting(false)
                    }

                    captureOverlay

                    CanvasBlockLayer(session: session)
                        .allowsHitTesting(session.mode.allowsBlockHitTesting)
                }
                .frame(width: CGFloat(session.contentWidth), height: CGFloat(session.contentHeight))
                .scaleEffect(CGFloat(session.transform.scale), anchor: .topLeading)
                .offset(x: CGFloat(session.transform.offsetX), y: CGFloat(session.transform.offsetY))
                .coordinateSpace(.named("canvas"))
                ZoomPanOverlay(session: session)
            }
            .clipped()
            .onAppear { configureViewport(proxy.size) }
            .onChange(of: proxy.size) { _, size in configureViewport(size) }
            .onChange(of: session.blocks) { growContent() }
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .bottomBar)
        .overlay(alignment: .bottom) {
            if session.letterArea != nil {
                BackspaceButton { session.letterBackspace() }
                    .padding(.bottom, 12)
            }
        }
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
            Text("strokes=\(visibleStrokes) saved=\(savedStrokes) blocks=\(session.blocks.count) zoom=\(String(format: "%.2f", session.transform.scale)) texture=\(session.pageTexture.rawValue) live=\(inkStore.liveStroke?.colorHex ?? "nil")")
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

    private func configureViewport(_ size: CGSize) {
        session.configureViewport(Size(width: Double(size.width), height: Double(size.height)))
        growContent()
    }

    /// Grow the page below the lowest block, stroke, or visible viewport edge
    /// so writing — and scrolling into empty space — never runs off the bottom.
    /// Idempotent; safe to call on every content change.
    private func growContent() {
        let blocksBottom = session.blocks.map(\.frame.maxY).max() ?? 0
        let strokesBottom = inkStore.strokes.map(\.bounds.maxY).max() ?? 0
        session.ensureContentHeight(bottom: max(blocksBottom, strokesBottom, session.visibleBottom))
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
    /// Bumped by the session after out-of-band store edits (letter commit);
    /// the coordinator rebuilds the live drawing when it changes.
    let rewriteToken: Int
    /// Called after new strokes are captured & persisted (recognition trigger).
    let onStrokeCaptured: () -> Void
    /// (visibleStrokes, savedStrokes) reported from the coordinator.
    let onStateChange: (Int, Int) -> Void
    /// First point of a newly started stroke (canvas points) — Letter Mode's
    /// commit-on-new-letter trigger.
    let onStrokeBegin: (Double, Double) -> Void

    func makeUIViewController(context: Context) -> CanvasViewController {
        let controller = CanvasViewController(recordID: recordID, store: store, inkStore: inkStore)
        controller.coordinator.onStateChange = onStateChange
        controller.coordinator.onStrokeCaptured = onStrokeCaptured
        controller.coordinator.onStrokeBegin = onStrokeBegin
        return controller
    }

    func updateUIViewController(_ uiViewController: CanvasViewController, context: Context) {
        uiViewController.coordinator.onStateChange = onStateChange
        uiViewController.coordinator.onStrokeCaptured = onStrokeCaptured
        uiViewController.coordinator.onStrokeBegin = onStrokeBegin
        if uiViewController.coordinator.lastRewriteToken != rewriteToken {
            uiViewController.coordinator.lastRewriteToken = rewriteToken
            uiViewController.coordinator.rewriteDrawingFromStore()
        }
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyFingerDrawingPolicy),
            name: .fingerDrawingChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyFingerDrawingPolicy()
        coordinator.reloadFromStore()
    }

    /// Re-reads the finger-painting preference so a Settings toggle applies to
    /// the open canvas immediately instead of on next open.
    @objc private func applyFingerDrawingPolicy() {
        let settings = AppSettings.shared
        canvas.drawingPolicy = CanvasInputPolicy.touchAllowedOnOpen(
            allowFingerDrawing: settings.allowFingerDrawing,
            touchLockedByPencil: settings.touchLockedByPencil
        ) ? .anyInput : .pencilOnly
    }

    /// Capture coordinator: renders the FULL live drawing (including the
    /// in-progress stroke, so ink appears while you paint) and persists each
    /// stroke as a `.stroke` block when it completes. Native ink is hidden
    /// beneath the opaque ink view, so this is the single source of truth.
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStateChange: ((Int, Int) -> Void)?
        var onStrokeCaptured: (() -> Void)?
        /// First point of a newly started stroke (canvas points).
        var onStrokeBegin: ((Double, Double) -> Void)?
        /// Last rewrite token consumed (see PKCanvasContainer).
        var lastRewriteToken = 0

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
        /// Live touch path for the in-progress stroke preview. Not tracked per
        /// touch: simultaneous multi-touch drawing is rare and a one-frame
        /// polyline jump self-corrects on the next event.
        private var livePoints: [CGPoint] = []
        private var liveTracking = false
        private var liveColorHex = "#000000"
        private var liveWidth = 3.0
        private var lastLivePush: TimeInterval = 0

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

        /// Unconditional rebuild of the live drawing and ink store from the
        /// store's stroke blocks. Unlike `reloadFromStore` (which skips when
        /// counts match), this runs after out-of-band payload edits such as a
        /// letter-mode commit that rewrote points without changing the count.
        func rewriteDrawingFromStore() {
            guard let store, let recordID, let canvas else { return }
            let strokeBlocks = (try? store.strokeBlocks(in: recordID)) ?? []
            let strokes = strokeBlocks.compactMap { block -> StrokeData? in
                guard case .stroke(let list, _, _) = block.payload, let first = list.first else { return nil }
                return first
            }
            rendered = strokes
            renderedCount = strokes.count
            persistedCount = strokes.count
            inkStore?.load(strokes)
            canvas.drawing = PKStrokeConverter.drawing(from: strokes)
            onStateChange?(canvas.drawing.strokes.count, persistedCount)
        }

        func attach(to canvas: PKCanvasView) {
            let picker = PKToolPicker()
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            self.picker = picker
            if let capture = canvas as? CaptureCanvasView {
                capture.onLiveTouch = { [weak self] point, type, ended in
                    self?.handleLiveTouch(point: point, type: type, ended: ended)
                }
            }
            DispatchQueue.main.async {
                canvas.becomeFirstResponder()
                picker.setVisible(true, forFirstResponder: canvas)
            }
        }

        /// Snapshot the live tool's color/width against the canvas's own
        /// traits. Same lesson as the normal-mode hex fix (dynamic `.label`
        /// must be resolved, not read raw) but scoped to `canvas.traitCollection`:
        /// the ambient `UITraitCollection.current` is wrong during touch
        /// dispatch, which is what turned white picker ink black in Letter Mode.
        private func snapshotLiveTool(from canvas: PKCanvasView) {
            if let ink = canvas.tool as? PKInkingTool {
                liveColorHex = ink.color.hexString(resolvedWith: canvas.traitCollection)
                liveWidth = Double(ink.width)
            }
        }

        /// Reliable stroke-begin signal from PencilKit — fires even when touch
        /// delivery is delayed, so a new stroke never inherits a previous
        /// stroke's points or its stale `#000000` default color.
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            livePoints = []
            snapshotLiveTool(from: canvasView)
        }

        /// Live touch path for the in-progress stroke preview, so ink appears
        /// while painting even under the opaque letter layer. Pencil always
        /// draws; finger only when the policy allows touch.
        private func handleLiveTouch(point: CGPoint, type: UITouch.TouchType, ended: Bool) {
            guard let canvas else {
                livePoints = []
                liveTracking = false
                inkStore?.clearLiveStroke()
                return
            }
            // End-of-stroke always resets, even for non-drawing touches —
            // otherwise the next stroke inherits stale points/color.
            if ended {
                livePoints = []
                liveTracking = false
                inkStore?.clearLiveStroke()
                return
            }
            let drawable = type == .pencil || canvas.drawingPolicy == .anyInput
            guard drawable else { return }
            if !liveTracking {
                liveTracking = true
                livePoints = []
                onStrokeBegin?(point.x, point.y)
            }
            // Refresh every event, not just at stroke start: the picker can
            // change mid-stroke and per-event sampling can't go stale.
            snapshotLiveTool(from: canvas)
            livePoints.append(point)
            // Touch streams can exceed display refresh; throttle preview pushes.
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastLivePush >= 1 / 60 else { return }
            lastLivePush = now
            let pts = livePoints.map {
                StrokePoint(location: Point(x: $0.x, y: $0.y), timestampOffset: 0, width: liveWidth, force: 0.5, azimuth: 0, altitude: 0)
            }
            inkStore?.setLiveStroke(StrokeData(points: pts, colorHex: liveColorHex, baseWidth: liveWidth))
        }

        /// Fires when the drawing changes (a stroke is added on completion).
        /// Persist any newly-completed strokes as `.stroke` blocks; native
        /// PKCanvasView rendering provides the live ink the user sees.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let all = canvasView.drawing.strokes
            updateRendered(from: all, traits: canvasView.traitCollection)
            if all.count > persistedCount {
                let newStrokes = all[persistedCount...].map { PKStrokeConverter.strokeData(from: $0, traits: canvasView.traitCollection) }
                persist(added: newStrokes)
                persistedCount = all.count
                onStrokeCaptured?()
            } else if all.count < persistedCount {
                removeLastStrokeBlocks(persistedCount - all.count)
                persistedCount = all.count
            }
            onStateChange?(all.count, persistedCount)
        }

        /// Safety flush in case a stroke completes without a drawing-did-change
        /// (no-op when `persistedCount` is already current).
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            persistCompleted(from: canvasView.drawing.strokes, traits: canvasView.traitCollection)
            // Safety: touches don't always arrive (the "line only on lift"
            // case) — never leave a stale preview or tracking flag behind.
            livePoints = []
            liveTracking = false
            inkStore?.clearLiveStroke()
        }

        private func updateRendered(from all: [PKStroke], traits: UITraitCollection) {
            guard let inkStore else { return }
            if all.count > renderedCount {
                let new = all[renderedCount...].map { PKStrokeConverter.strokeData(from: $0, traits: traits) }
                rendered.append(contentsOf: new)
                renderedCount = all.count
            } else if all.count < renderedCount {
                rendered = Array(rendered.prefix(all.count))
                renderedCount = all.count
            } else if !all.isEmpty {
                // Same count but the last stroke is in progress — re-render it.
                rendered[all.count - 1] = PKStrokeConverter.strokeData(from: all[all.count - 1], traits: traits)
            }
            inkStore.load(rendered)
        }

        private func persistCompleted(from all: [PKStroke], traits: UITraitCollection) {
            guard let store, let recordID else { return }
            guard all.count > persistedCount else { return }
            let newStrokes = all[persistedCount...].map { PKStrokeConverter.strokeData(from: $0, traits: traits) }
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

/// Dashed baseline guide for Letter Mode, drawn in canvas coordinates so it
/// zooms and pans with the writing area.
private struct LetterBaselineGuide: View {
    let area: Rect
    let baselineY: Double
    let scale: Double

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: CGFloat(area.minX), y: CGFloat(baselineY)))
            path.addLine(to: CGPoint(x: CGFloat(area.maxX), y: CGFloat(baselineY)))
        }
        .stroke(
            Color.accentColor.opacity(0.45),
            style: StrokeStyle(
                lineWidth: 1.5 / CGFloat(max(scale, 0.01)),
                dash: [6 / CGFloat(max(scale, 0.01)), 5 / CGFloat(max(scale, 0.01))]
            )
        )
        .allowsHitTesting(false)
    }
}

/// Letter Mode backspace: tap deletes the last committed letter (with any
/// folded diacritic); press-and-hold repeats. Screen-space, bottom center.
private struct BackspaceButton: View {
    let action: () -> Void
    @State private var repeatTimer: Timer?

    var body: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Circle())
            .contentShape(Circle())
            .accessibilityIdentifier("letterBackspace")
            .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 30) {
                // (unreachable with .infinity duration) perform stops the repeat
                stopRepeat()
            } onPressingChanged: { pressing in
                if pressing {
                    action()
                    startRepeat()
                } else {
                    stopRepeat()
                }
            }
    }

    private func startRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { _ in
            DispatchQueue.main.async { action() }
        }
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// PKCanvasView subclass that detects the first Apple Pencil touch so the
/// canvas can switch from `.anyInput` to `.pencilOnly` (touch painting off).
/// Phase 3 uses it as the capture-only canvas.
private final class CaptureCanvasView: PKCanvasView {
    var onPencilFirstUse: (() -> Void)?
    /// Live touch path in canvas-view points (== canvas points: the view is
    /// laid out at content size, so local coords need no unscaling).
    /// Parameters: location, touch type, ended/cancelled.
    var onLiveTouch: ((CGPoint, UITouch.TouchType, Bool) -> Void)?
    private var pencilSeen = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !pencilSeen, touches.contains(where: { $0.type == .pencil }) {
            pencilSeen = true
            onPencilFirstUse?()
        }
        for touch in touches {
            onLiveTouch?(touch.location(in: self), touch.type, false)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            onLiveTouch?(touch.location(in: self), touch.type, false)
        }
    }

    private func endLiveTouches(_ touches: Set<UITouch>) {
        for touch in touches {
            onLiveTouch?(touch.location(in: self), touch.type, true)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endLiveTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endLiveTouches(touches)
    }
}
