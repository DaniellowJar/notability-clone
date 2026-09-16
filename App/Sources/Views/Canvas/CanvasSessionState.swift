import NotabilityCore
import Foundation
import Observation

/// Mutable canvas state for one Record: current mode, loaded blocks, and the
/// live area-selection marquee. Persists every change through the store.
@Observable
final class CanvasSessionState {
    var mode: CanvasMode = .draw
    var blocks: [CanvasBlock] = []
    var marquee: Rect?
    var errorMessage: String?

    private(set) var recordID: UUID?
    private(set) var store: NotabilityStore?

    private var marqueeStart: Point?
    private var pendingRef: String?
    private var pendingThumbRef: String?
    private var textSaveWorkItem: DispatchWorkItem?
    private var pendingText: (id: UUID, payload: BlockPayload)?
    private var pendingFrame: (id: UUID, frame: Rect)?

    // MARK: - Letter Mode v2 (write-zoom-commit)

    /// Seconds of no new ink before the current line commits.
    static let letterSettleDelay = 0.8
    /// Viewport fraction where the follow camera parks the writing position.
    static let letterFollowThreshold = 0.7
    /// Committed glyph height in page points at 100% zoom.
    static let letterCommittedHeight = 12.0
    /// Gap below a committed line before the next one starts.
    static let letterLineGap = 8.0
    /// Screen offset of the letter area's top edge when zoomed to fit.
    static let letterTopInset = 140.0

    /// Active writing area in canvas points; nil when letter mode is off.
    var letterArea: Rect?
    /// Y (canvas points) where the next committed line starts.
    var letterCursorY: Double = 0
    /// Store stroke-block count where the current line started.
    var letterLineStartCount = 0
    /// Bumped whenever the canvas drawing must be rebuilt from the store.
    var drawingRewriteToken = 0
    private var letterCommitWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    func load(recordID: UUID, store: NotabilityStore) {
        self.recordID = recordID
        self.store = store
        loadHeaderFormat()
        reload()
    }

    func loadHeaderFormat() {
        let settings = AppSettings.shared
        let dateFormat = settings.pageDateFormat.isEmpty
            ? PageHeaderFormat.default.dateFormat : settings.pageDateFormat
        let timeFormat = settings.pageTimeFormat.isEmpty
            ? PageHeaderFormat.default.timeFormat : settings.pageTimeFormat
        headerFormat = PageHeaderFormat(
            alignment: PageHeaderAlignment(rawValue: settings.pageHeaderAlignmentRaw) ?? .center,
            dateFormat: dateFormat,
            timeFormat: timeFormat
        )
    }

    func reload() {
        guard let recordID, let store else { return }
        do {
            // Ink strokes are `.stroke` blocks rendered by the custom ink layer;
            // this session drives the block overlay, so exclude them.
            blocks = try store.blocks(in: recordID).filter { $0.kind != .stroke }
        } catch {
            errorMessage = "Could not load blocks: \(error.localizedDescription)"
        }
    }

    func flushPendingSaves() {
        textSaveWorkItem?.cancel()
        textSaveWorkItem = nil
        if let (id, payload) = pendingText {
            pendingText = nil
            if let store { try? store.updateBlockPayload(id, payload: payload) }
        }
        if let (id, frame) = pendingFrame {
            pendingFrame = nil
            if let store { try? store.updateBlockFrame(id, frame: frame) }
        }
    }

    // MARK: - Page geometry & zoom

    /// Horizontal page margin (each side) inside the viewport.
    static let pageMargin = 16.0

    /// Screen = canvas * scale + offset. All stored coordinates stay in
    /// canvas points; gestures inverse-map through this.
    var transform = CanvasTransform.identity
    var contentWidth: Double = 0
    var contentHeight: Double = 0
    var viewport = Size.zero
    var headerFormat = PageHeaderFormat.default

    func configureViewport(_ size: Size) {
        viewport = size
        contentWidth = max(size.width - Self.pageMargin * 2, 1)
        if contentHeight < size.height { contentHeight = size.height }
    }

    /// Grow the page so `bottom` (lowest content Y in canvas points) stays
    /// covered with room to keep writing. Never shrinks.
    func ensureContentHeight(bottom: Double) {
        contentHeight = CanvasTransform.grownHeight(
            current: contentHeight,
            contentBottom: bottom,
            viewportHeight: viewport.height,
            padding: viewport.height * 0.5
        )
    }

    // MARK: - Pinch zoom & pan (driven by the zoom overlay, screen points)

    private var pinchBase = CanvasTransform.identity

    func pinchBegan() {
        pinchBase = transform
    }

    func pinchChanged(relativeScale: Double, anchorScreen: Point) {
        transform = pinchBase.zoomed(to: pinchBase.scale * relativeScale, anchorScreen: anchorScreen)
    }

    func pinchEnded() {
        pinchBase = transform
    }

    func panBy(_ delta: Point) {
        transform = transform.panned(by: delta)
    }

    // MARK: - Tools

    func startTextTool() {
        mode = .areaSelect(.newTextBlock)
        marquee = nil
        marqueeStart = nil
    }

    func startSelectTool() {
        mode = .areaSelect(.selectBlocks)
        marquee = nil
        marqueeStart = nil
    }

    func startPlaceImage(ref: String) {
        pendingRef = ref
        pendingThumbRef = nil
        mode = .tapToPlace(.image)
    }

    func startPlacePDF(ref: String, thumbRef: String) {
        pendingRef = ref
        pendingThumbRef = thumbRef
        mode = .tapToPlace(.pdf)
    }

    func startPlaceCalc() {
        pendingRef = nil
        pendingThumbRef = nil
        mode = .tapToPlace(.calc)
    }

    /// Enter letter-area selection (marquee); the toolbar Done path cancels.
    func startLetterArea() {
        mode = .areaSelect(.letterArea)
        marquee = nil
        marqueeStart = nil
    }

    /// Zoom the marquee area across the screen and begin the writing session.
    func enterLetterArea(_ rect: Rect) {
        guard let store, let recordID else { return }
        let scale = LetterMode.zoomToFit(areaWidth: rect.size.width, viewportWidth: viewport.width)
        transform = CanvasTransform(
            scale: scale,
            offsetX: -rect.minX * scale,
            offsetY: Self.letterTopInset - rect.minY * scale
        )
        letterArea = rect
        letterCursorY = rect.minY
        letterLineStartCount = (try? store.strokeBlocks(in: recordID).count) ?? 0
        mode = .draw
    }

    /// Done / pinch-exit: commit any settled line, then leave letter mode.
    /// Zoom is left as-is — pinch out to return to 100%.
    func exitLetterMode() {
        commitLetterLine()
        letterCommitWorkItem?.cancel()
        letterCommitWorkItem = nil
        letterArea = nil
    }

    /// Called with the newest captured point (canvas coordinates) while letter
    /// mode is active: pans the camera to follow writing, extends the area and
    /// page downward as needed, and (re)starts the settle timer.
    func trackLetterWriting(x: Double, y: Double) {
        guard letterArea != nil else { return }
        let w = max(viewport.width, 1)
        let h = max(viewport.height, 1)
        let s = max(transform.scale, 0.01)
        transform = CanvasTransform(
            scale: transform.scale,
            offsetX: LetterMode.followOffset(writingCanvasX: x, scale: transform.scale, offsetX: transform.offsetX, viewportWidth: w),
            offsetY: LetterMode.followOffset(writingCanvasX: y, scale: transform.scale, offsetX: transform.offsetY, viewportWidth: h, threshold: 0.8)
        )
        if var area = letterArea {
            let needed = y - area.minY + h / s * 0.5
            if needed > area.size.height {
                area.size.height = needed
                letterArea = area
            }
        }
        ensureContentHeight(bottom: y + h / s * 0.5)
        scheduleLetterCommit()
    }

    func scheduleLetterCommit() {
        guard letterArea != nil else { return }
        letterCommitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitLetterLine() }
        letterCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.letterSettleDelay, execute: work)
    }

    /// Normalize the settled line to 12px in place (same block IDs, stable
    /// counts so undo math keeps working), then request a drawing rebuild.
    func commitLetterLine() {
        guard let store, let recordID, let area = letterArea else { return }
        letterCommitWorkItem?.cancel()
        letterCommitWorkItem = nil
        let all = (try? store.strokeBlocks(in: recordID)) ?? []
        let start = min(letterLineStartCount, all.count)
        guard start < all.count else {
            letterLineStartCount = all.count
            return
        }
        let line = Array(all[start...])
        let padded = Rect(x: area.minX - 8, y: area.minY - 8,
                          width: area.size.width + 16, height: area.size.height + 16)
        let inArea = line.filter { $0.frame.intersects(padded) }
        guard !inArea.isEmpty else {
            letterLineStartCount = all.count
            return
        }
        var box = inArea[0].frame
        for b in inArea.dropFirst() { box = Rect.union(box, b.frame) }
        let scale = LetterMode.normalizeScale(lineHeight: box.size.height, targetHeight: Self.letterCommittedHeight)
        let anchor = Point(x: area.minX, y: letterCursorY)
        do {
            for block in inArea {
                guard case .stroke(let strokes, let text, let corrected) = block.payload else { continue }
                let mapped = strokes.map { s -> StrokeData in
                    var c = s
                    c.points = s.points.map { pt in
                        var q = pt
                        q.location = Point(
                            x: anchor.x + (pt.location.x - box.minX) * scale,
                            y: anchor.y + (pt.location.y - box.minY) * scale
                        )
                        return q
                    }
                    // Fresh canonical geometry; stale overlays would misrender.
                    c.correctedPoints = nil
                    c.transform = nil
                    return c
                }
                try store.updateBlockPayload(block.id, payload: .stroke(mapped, recognizedText: text, corrected: corrected))
            }
            letterCursorY += Self.letterCommittedHeight + Self.letterLineGap
            letterLineStartCount = (try? store.strokeBlocks(in: recordID).count) ?? 0
            drawingRewriteToken += 1
        } catch {
            errorMessage = "Could not commit letter line: \(error.localizedDescription)"
        }
    }

    func cancelTool() {
        mode = .draw
        marquee = nil
        marqueeStart = nil
        pendingRef = nil
        pendingThumbRef = nil
        // Switching tools abandons the letter area; raw strokes stay persisted.
        letterCommitWorkItem?.cancel()
        letterCommitWorkItem = nil
        letterArea = nil
    }

    // MARK: - Area selection

    func beginOrUpdateMarquee(at point: Point) {
        if marqueeStart == nil { marqueeStart = point }
        guard let start = marqueeStart else { return }
        marquee = AreaSelection.normalize(from: start, to: point)
    }

    func endAreaSelect(intent: SelectionIntent) {
        let rect = marquee
        marquee = nil
        marqueeStart = nil
        guard let rect, AreaSelection.isValid(rect) else {
            mode = .draw
            return
        }
        switch intent {
        case .newTextBlock:
            insertTextBlock(frame: rect)
        case .selectBlocks:
            guard let top = CanvasHitTester.blocks(intersecting: rect, in: blocks).last else {
                mode = .draw
                return
            }
            selectBlock(top.id)
        case .letterArea:
            enterLetterArea(rect)
        }
    }

    // MARK: - Placement

    func place(intent: PlacementIntent, at point: Point) {
        switch intent {
        case .image, .pdf:
            guard let ref = pendingRef else {
                mode = .draw
                return
            }
            switch intent {
            case .image:
                insertImageBlock(ref: ref, at: point)
            case .pdf:
                insertPDFBlock(ref: ref, thumbRef: pendingThumbRef ?? "", at: point)
            case .calc:
                break
            }
        case .calc:
            insertCalcBlock(at: point)
        }
    }

    // MARK: - Block operations

    func insertTextBlock(frame: Rect) {
        guard let store, let recordID else { return }
        let fontSize = TextBlockLayout.defaultFontSize
        let sized = TextBlockLayout.autoFrame(marquee: frame, fontSize: fontSize, text: "")
        do {
            let block = try store.addBlock(
                in: recordID, kind: .text, frame: sized,
                payload: .text(TextBlockPayload(text: "", fontSize: fontSize))
            )
            blocks = try store.blocks(in: recordID)
            selectBlock(block.id)
        } catch {
            errorMessage = "Could not add text block: \(error.localizedDescription)"
        }
    }

    func insertImageBlock(ref: String, at point: Point) {
        guard let store, let recordID else { return }
        let size = Size(width: 240, height: 180)
        let frame = Rect(
            x: max(0, point.x - size.width / 2),
            y: max(0, point.y - size.height / 2),
            width: size.width, height: size.height
        )
        do {
            _ = try store.addBlock(in: recordID, kind: .image, frame: frame, payload: .image(ImageBlockPayload(imageRef: ref)))
            blocks = try store.blocks(in: recordID)
            cancelTool()
        } catch {
            errorMessage = "Could not insert image: \(error.localizedDescription)"
        }
    }

    func insertPDFBlock(ref: String, thumbRef: String, at point: Point) {
        guard let store, let recordID else { return }
        let size = Size(width: 200, height: 260)
        let frame = Rect(
            x: max(0, point.x - size.width / 2),
            y: max(0, point.y - size.height / 2),
            width: size.width, height: size.height
        )
        do {
            _ = try store.addBlock(
                in: recordID, kind: .pdfPage, frame: frame,
                payload: .pdfPage(PDFPageBlockPayload(sourcePDFRef: ref, pageIndex: 0, renderedImageRef: thumbRef))
            )
            blocks = try store.blocks(in: recordID)
            cancelTool()
        } catch {
            errorMessage = "Could not insert PDF: \(error.localizedDescription)"
        }
    }

    func insertCalcBlock(at point: Point) {
        guard let store, let recordID else { return }
        let size = Size(width: 220, height: 110)
        let frame = Rect(
            x: max(0, point.x - size.width / 2),
            y: max(0, point.y - size.height / 2),
            width: size.width, height: size.height
        )
        do {
            _ = try store.addBlock(
                in: recordID, kind: .calc, frame: frame,
                payload: .calc(CalcBlockPayload(expression: "", result: "", isEditable: true))
            )
            blocks = try store.blocks(in: recordID)
            cancelTool()
        } catch {
            errorMessage = "Could not add calculator: \(error.localizedDescription)"
        }
    }

    // MARK: - Calculator

    /// Evaluates locally when possible; returns nil when the expression needs AI.
    func evaluate(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        do {
            let value = try ExpressionEvaluator.evaluate(trimmed)
            return format(value)
        } catch {
            return nil
        }
    }

    func setCalcExpression(_ id: UUID, expression: String) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .calc(var payload) = blocks[idx].payload else { return }
        payload.expression = expression
        if let result = evaluate(expression) {
            payload.result = result
        }
        blocks[idx] = withPayload(.calc(payload), at: idx)
        scheduleTextSave(id: id, payload: .calc(payload))
    }

    func setCalcResult(_ id: UUID, result: String) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .calc(var payload) = blocks[idx].payload else { return }
        payload.result = result
        blocks[idx] = withPayload(.calc(payload), at: idx)
        scheduleTextSave(id: id, payload: .calc(payload))
    }

    private func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    func selectBlock(_ id: UUID) {
        mode = .editingBlock(id)
    }

    func deselect() {
        flushPendingSaves()
        mode = .draw
    }

    func moveBlock(id: UUID, to origin: Point) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[idx].frame.origin = origin
    }

    func finishMoveBlock(id: UUID) {
        guard let store, let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        do {
            try store.updateBlockFrame(id, frame: blocks[idx].frame)
        } catch {
            errorMessage = "Could not save block position: \(error.localizedDescription)"
        }
    }

    func deleteBlock(_ id: UUID) {
        guard let store, let recordID,
              let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        let block = blocks[idx]
        do {
            try store.deleteBlock(id)
            let refs = BlockPayload.references(in: block)
            BlobStore.shared.deleteIfUnreferenced(refs: refs, among: blocks)
            blocks = try store.blocks(in: recordID)
            if mode.editingBlockID == id { mode = .draw }
        } catch {
            errorMessage = "Could not delete block: \(error.localizedDescription)"
        }
    }

    /// Inserts an image block from a PDF-extract raster below its source block.
    func insertImageFromExtract(_ extractedRef: String, near blockID: UUID) {
        guard let store, let recordID,
              let idx = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let source = blocks[idx]
        let frame = Rect(
            x: source.frame.minX,
            y: source.frame.maxY + 12,
            width: min(source.frame.size.width * 0.7, 300),
            height: 260
        )
        do {
            _ = try store.addBlock(in: recordID, kind: .image, frame: frame, payload: .image(ImageBlockPayload(imageRef: extractedRef)))
            blocks = try store.blocks(in: recordID).filter { $0.kind != .stroke }
        } catch {
            errorMessage = "Could not add extracted page: \(error.localizedDescription)"
        }
    }

    /// Swaps an image block's blob (e.g. for a background-removed PNG).
    func replaceImageRef(_ id: UUID, ref: String, backgroundRemoved: Bool) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .image(var payload) = blocks[idx].payload else { return }
        payload.imageRef = ref
        payload.backgroundRemoved = backgroundRemoved
        blocks[idx] = withPayload(.image(payload), at: idx)
        scheduleTextSave(id: id, payload: .image(payload))
    }

    // MARK: - Text block editing

    func setText(_ id: UUID, text: String) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .text(var payload) = blocks[idx].payload else { return }
        payload.text = text
        let block = withPayload(.text(payload), at: idx)
        blocks[idx] = block
        scheduleTextSave(id: id, payload: .text(payload))
    }

    func setTextFontSize(_ id: UUID, size: Double) {
        let clamped = TextBlockLayout.clampedFontSize(size)
        guard let idx = blocks.firstIndex(where: { $0.id == id }),
              case .text(var payload) = blocks[idx].payload else { return }
        guard abs(payload.fontSize - clamped) > 0.01 else { return }
        payload.fontSize = clamped
        blocks[idx] = withPayload(.text(payload), at: idx)
        scheduleTextSave(id: id, payload: .text(payload))
    }

    func setTextBlockHeight(_ id: UUID, height: Double) {
        guard let idx = blocks.firstIndex(where: { $0.id == id }) else { return }
        let fontSize = blocks[idx].textPayload?.fontSize ?? TextBlockLayout.defaultFontSize
        let minHeight = TextBlockLayout.lineHeight(fontSize: fontSize) + TextBlockLayout.verticalPadding * 2
        let newHeight = max(height, minHeight)
        guard abs(newHeight - blocks[idx].frame.size.height) > 1 else { return }
        blocks[idx].frame.size.height = newHeight
        if let store {
            pendingFrame = (id, blocks[idx].frame)
            frameSaveWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let pending = self.pendingFrame { try? store.updateBlockFrame(pending.id, frame: pending.frame) }
                self.pendingFrame = nil
            }
            frameSaveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    private var frameSaveWorkItem: DispatchWorkItem?

    private func withPayload(_ payload: BlockPayload, at idx: Int) -> CanvasBlock {
        let block = blocks[idx]
        return CanvasBlock(
            id: block.id, recordId: block.recordId, kind: block.kind,
            frame: block.frame, zIndex: block.zIndex, timestamp: block.timestamp,
            payload: payload, modifiedAt: block.modifiedAt
        )
    }

    private func scheduleTextSave(id: UUID, payload: BlockPayload) {
        pendingText = (id, payload)
        textSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let store else { return }
            if let pending = self.pendingText {
                try? store.updateBlockPayload(pending.id, payload: pending.payload)
            }
            self.pendingText = nil
        }
        textSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

extension CanvasBlock {
    var textPayload: TextBlockPayload? {
        if case .text(let p) = payload { p } else { nil }
    }
    var imageRef: String? {
        if case .image(let p) = payload { p.imageRef } else { nil }
    }
    var pdfSourceRef: String? {
        if case .pdfPage(let p) = payload { p.sourcePDFRef } else { nil }
    }
    var pdfThumbRef: String? {
        if case .pdfPage(let p) = payload { p.renderedImageRef.isEmpty ? nil : p.renderedImageRef } else { nil }
    }
    var calcExpression: String? {
        if case .calc(let p) = payload { p.expression } else { nil }
    }
    var calcResult: String? {
        if case .calc(let p) = payload { p.result } else { nil }
    }
}
