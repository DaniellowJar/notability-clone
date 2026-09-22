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

    /// Seconds of no new ink before the current line commits (fallback path —
    /// the primary commit trigger is starting a new letter, see
    /// `handleLetterStrokeBegin`).
    static let letterSettleDelay = 0.4
    /// Stroke-to-stroke silence (s) from which a new stroke counts as a new
    /// letter and force-commits the ink before it. Shorter gaps are treated
    /// as one letter's own strokes (dots, t-crosses) and never split it.
    static let letterImmediateGap = 0.35
    /// Viewport fraction where the follow camera parks the writing position.
    static let letterFollowThreshold = 0.7
    /// Committed glyph height in page points at 100% zoom (ascender-to-baseline).
    static let letterCommittedHeight = LetterMode.targetGlyphHeight
    /// On-screen (unzoomed) height of naturally written letters, used only to
    /// tell a lone diacritic from a lone small letter when a settle commits
    /// one cluster.
    static let naturalGlyphScreenHeight = 60.0
    /// Screen offset of the letter area's top edge when zoomed to fit.
    static let letterTopInset = 140.0

    /// A committed letter (its stroke blocks) popped by the backspace button.
    struct LetterUndoGroup {
        var ids: [UUID]
        /// Committed bounds of this letter (omit the diacritic offset).
        var bounds: Rect
        /// letterCursor.y of the line this letter sits on.
        var lineTop: Double
        /// Normalize scale and raw baseline of that line's commit — reused to
        /// map a late-drawn diacritic back onto this letter.
        var scale: Double
        var rawBaseline: Double
    }

    /// Active writing area in canvas points; nil when letter mode is off.
    var letterArea: Rect?
    /// Next write position in canvas points. Advances right along the line
    /// and wraps down at the area's right edge (never blindly per pause).
    var letterCursor = Point(x: 0, y: 0)
    /// Store stroke-block count where the current line started.
    var letterLineStartCount = 0
    /// Committed letters, for the backspace button and late-diacritic
    /// merge-back.
    var letterUndoGroups: [LetterUndoGroup] = []
    /// CFAbsoluteTime of the last completed letter-mode stroke.
    var letterLastActivity: TimeInterval = 0
    /// Bumped whenever the canvas drawing must be rebuilt from the store.
    var drawingRewriteToken = 0
    private var letterCommitWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    func load(recordID: UUID, store: NotabilityStore) {
        self.recordID = recordID
        self.store = store
        loadHeaderFormat()
        pageTexture = (try? store.texture(for: recordID)) ?? .plain
        reload()
    }

    func loadHeaderFormat() {
        let settings = AppSettings.shared
        let dateFormat = settings.pageDateFormat.isEmpty
            ? PageHeaderFormat.defaultDateFormat : settings.pageDateFormat
        let timeFormat = settings.pageTimeFormat.isEmpty
            ? PageHeaderFormat.defaultTimeFormat : settings.pageTimeFormat
        headerFormat = PageHeaderFormat(
            alignment: PageHeaderAlignment(rawValue: settings.pageHeaderAlignmentRaw) ?? .center,
            dateFormat: dateFormat,
            timeFormat: timeFormat
        )
    }

    func setPageTexture(_ texture: PageTexture) {
        guard let recordID, let store else { return }
        do {
            try store.setRecordTexture(texture, for: recordID)
            pageTexture = texture
        } catch {
            errorMessage = "Could not change page texture: \(error.localizedDescription)"
        }
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
    /// This page's background pattern (per-page setting, persisted).
    var pageTexture = PageTexture.plain

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

    /// Canvas-space Y of the viewport's bottom edge at the current transform.
    var visibleBottom: Double {
        CanvasTransform.visibleBottom(
            viewportHeight: viewport.height,
            offsetY: transform.offsetY,
            scale: transform.scale
        )
    }

    /// Grow for scrolling: keep room below what the user can currently see,
    /// so panning into empty space extends the page ahead of them.
    func growForViewport() {
        ensureContentHeight(bottom: visibleBottom)
    }

    // MARK: - Pinch zoom & pan (one unified two-finger gesture, screen points)

    /// Apply one incremental Maps-style frame: zoom about the moving anchor,
    /// then translate. Called on every gesture event from the current
    /// transform — never recomputed from a gesture-start base.
    func applyZoomPan(scaleRatio: Double, anchorScreen: Point, pan: Point) {
        transform = transform.zoomPanStep(scaleRatio: scaleRatio, anchorScreen: anchorScreen, pan: pan)
        growForViewport()
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
        letterCursor = Point(x: rect.minX, y: rect.minY)
        letterLineStartCount = (try? store.strokeBlocks(in: recordID).count) ?? 0
        letterUndoGroups = []
        letterLastActivity = 0
        mode = .draw
    }

    /// Done / pinch-exit: commit any settled line, then leave letter mode.
    /// Zoom is left as-is — pinch out to return to 100%.
    func exitLetterMode() {
        commitLetterLine()
        letterCommitWorkItem?.cancel()
        letterCommitWorkItem = nil
        letterArea = nil
        letterUndoGroups = []
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
        letterLastActivity = CFAbsoluteTimeGetCurrent()
        scheduleLetterCommit()
    }

    /// First point of a newly started stroke in letter mode. After enough
    /// silence this is "a new letter begins": force-commit everything before
    /// it — unless the stroke starts high on the line, which is more likely
    /// its own diacritic (i-dot, j-dot, Š, ż) than the next letter, so the
    /// fallback timer decides. Diacritics drawn within the silence window
    /// never hit this path at all.
    func handleLetterStrokeBegin(x: Double, y: Double) {
        guard let store, let recordID, letterArea != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let silence = now - letterLastActivity
        letterLastActivity = now
        guard silence >= Self.letterImmediateGap else { return }
        let all = (try? store.strokeBlocks(in: recordID)) ?? []
        let start = min(letterLineStartCount, all.count)
        guard start < all.count else { return }
        var box = all[start].frame
        for b in all[(start + 1)...] { box = Rect.union(box, b.frame) }
        guard box.size.height > 0 else { return }
        if y >= box.minY + box.size.height * 0.6 {
            // Starting in the baseline band: next letter, commit what came before.
            commitLetterLine()
        } else {
            // High start: likely a late diacritic, keep the line together.
            scheduleLetterCommit()
        }
    }

    func scheduleLetterCommit() {
        guard letterArea != nil else { return }
        letterCommitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commitLetterLine() }
        letterCommitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.letterSettleDelay, execute: work)
    }

    /// Normalize the settled line to the committed glyph height, anchored on
    /// its baseline so descenders (j, g, q) hang below the baseline instead of
    /// inflating and shrinking everything. Also scales stroke widths by the
    /// same factor (raw capture ink keeps its fat width otherwise), records
    /// per-letter undo groups for backspace, and advances the cursor with a
    /// proportional (glyph-height-relative) gap.
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
        let entries: [(block: CanvasBlock, stroke: StrokeData, text: String, corrected: Bool)] = inArea.compactMap { block in
            guard case .stroke(let list, let text, let corrected) = block.payload, let s = list.first else { return nil }
            return (block, s, text, corrected)
        }
        guard !entries.isEmpty else {
            letterLineStartCount = all.count
            return
        }
        let clusters = LetterMode.letterClusters(strokes: entries.map(\.stroke))
        let bounds = clusters.compactMap(LetterMode.clusterBounds)
        let diacritics = LetterMode.diacriticIndices(bounds: bounds)

        // A settle split a letter from its own diacritic (the i-dot drawn long
        // after): the line is diacritic-only — fold it into the last committed
        // letter instead of publishing a blob of its own.
        if !bounds.isEmpty, diacritics.count == bounds.count {
            foldDiacritic(entries: entries,
                          bounds: bounds,
                          finalCount: all.count, store: store)
            return
        }
        guard let metrics = LetterMode.lineMetrics(
            clusters: clusters, diacritics: diacritics, targetHeight: Self.letterCommittedHeight
        ) else {
            letterLineStartCount = all.count
            return
        }
        // A lone tiny cluster can still be a stranded diacritic the size
        // heuristic missed — judge it against the canvas-scale estimate.
        if clusters.count == 1, bounds.indices.contains(0) {
            let natural = LetterMode.naturalWritingHeight(
                screenHeight: Self.naturalGlyphScreenHeight, scale: transform.scale
            )
            if bounds[0].size.height < 0.4 * natural {
                foldDiacritic(entries: entries,
                              bounds: bounds,
                              finalCount: all.count, store: store)
                return
            }
        }

        let scale = metrics.scale
        let box = clusters.flatMap { $0.map(\.bounds) }.reduce(bounds[0]) { Rect.union($0, $1) }
        let rawBaseline = metrics.baseline
        let anchor = letterCursor
        /// Baseline-anchored normalize: letter bodies land exactly
        /// [cursor.y, cursor.y + 12]; descenders hang below and diacritics
        /// above, at their natural relative offsets from the baseline.
        func map(_ pt: Point) -> Point {
            Point(
                x: anchor.x + (pt.x - box.minX) * scale,
                y: anchor.y + Self.letterCommittedHeight + (pt.y - rawBaseline) * scale
            )
        }
        func mapStroke(_ s: StrokeData) -> StrokeData {
            var c = s
            c.points = s.points.map {
                var q = $0
                q.location = map($0.location)
                q.width *= scale
                return q
            }
            c.baseWidth *= scale
            // Fresh canonical geometry; stale overlays would misrender.
            c.correctedPoints = nil
            c.transform = nil
            return c
        }

        do {
            var groups: [LetterUndoGroup] = []
            var consumed = 0
            for (ci, cluster) in clusters.enumerated() {
                let slice = Array(entries[consumed..<(consumed + cluster.count)])
                consumed += cluster.count
                let mapped = slice.map { mapStroke($0.stroke) }
                let mappedBounds = LetterMode.clusterBounds(mapped) ?? bounds[ci]
                let ids = slice.map(\.block.id)
                if diacritics.contains(ci),
                   let gi = groups.lastIndex(where: {
                       $0.bounds.maxX >= mappedBounds.minX - LetterMode.wordGap(targetHeight: Self.letterCommittedHeight)
                   }) {
                    groups[gi].ids += ids
                    groups[gi].bounds = Rect.union(groups[gi].bounds, mappedBounds)
                } else {
                    groups.append(LetterUndoGroup(
                        ids: ids, bounds: mappedBounds, lineTop: anchor.y,
                        scale: scale, rawBaseline: rawBaseline
                    ))
                }
                for (i, entry) in slice.enumerated() {
                    try store.updateBlockPayload(
                        entry.block.id,
                        payload: .stroke([mapped[i]], recognizedText: entry.text, corrected: entry.corrected)
                    )
                    try store.updateBlockFrame(entry.block.id, frame: mappedBounds)
                }
            }
            letterUndoGroups += groups
            // Advance along the line; wrap down only at the area's right edge.
            letterCursor.x += box.size.width * scale + LetterMode.wordGap(targetHeight: Self.letterCommittedHeight)
            if letterCursor.x >= area.maxX - LetterMode.wordGap(targetHeight: Self.letterCommittedHeight) {
                letterCursor = Point(
                    x: area.minX,
                    y: letterCursor.y + Self.letterCommittedHeight + LetterMode.lineGap(targetHeight: Self.letterCommittedHeight)
                )
            }
            letterLineStartCount = (try? store.strokeBlocks(in: recordID).count) ?? 0
            drawingRewriteToken += 1
        } catch {
            errorMessage = "Could not commit letter line: \(error.localizedDescription)"
        }
    }

    /// Late-drawn diacritic (i-dot, j-dot, Š, ż) that arrived after its letter
    /// already committed: rewrite the same stroke blocks so the mark sits
    /// where the letter's own commit would have placed it — top-centered over
    /// the last committed letter — and add its blocks to that letter's undo
    /// group so backspace removes it together with the letter.
    private func foldDiacritic(
        entries: [(block: CanvasBlock, stroke: StrokeData, text: String, corrected: Bool)],
        bounds: [Rect],
        finalCount: Int,
        store: NotabilityStore
    ) {
        guard !letterUndoGroups.isEmpty, let diaRaw = bounds.first else {
            // Nothing committed yet — leave raw ink in the area; a later
            // commit with context can still place it properly.
            letterLineStartCount = finalCount
            drawingRewriteToken += 1
            return
        }
        var last = letterUndoGroups.removeLast()
        let scale = last.scale
        let letter = last.bounds
        let dia = bounds.first!
        // Centered horizontally over the letter, its top a fraction of the
        // glyph height above the letter's top (accent position, not apxis).
        let anchorX = letter.minX + (letter.size.width - dia.size.width * scale) / 2
        let diaHeight = dia.size.height * scale
        let anchorY = letter.minY - diaHeight - 0.15 * Self.letterCommittedHeight
        do {
            var ids: [UUID] = []
            for entry in entries {
                guard case .stroke(let list, _, _) = entry.block.payload, let stroke = list.first else { continue }
                var c = stroke
                c.points = stroke.points.map {
                    var q = $0
                    q.location = Point(
                        x: anchorX + ($0.location.x - diaRaw.minX) * scale,
                        y: anchorY + ($0.location.y - diaRaw.minY) * scale
                    )
                    q.width *= scale
                    return q
                }
                c.baseWidth *= scale
                c.correctedPoints = nil
                c.transform = nil
                ids.append(entry.block.id)
                try store.updateBlockPayload(
                    entry.block.id,
                    payload: .stroke([c], recognizedText: entry.text, corrected: entry.corrected)
                )
                try store.updateBlockFrame(entry.block.id, frame: LetterMode.clusterBounds([c]) ?? entry.block.frame)
            }
            last.ids += ids
            // The dot sits above the letter's top — it doesn't widen the
            // group's horizontal bounds, so don't union them (that would mix
            // raw coordinates into mapped bounds).
            letterUndoGroups.append(last)
            drawingRewriteToken += 1
        } catch {
            errorMessage = "Could not fold diacritic: \(error.localizedDescription)"
        }
        letterLineStartCount = finalCount
    }

    /// Backspace button: delete the most-recently committed letter (with any
    /// diacritics folded into it) and restore the cursor to its position.
    func letterBackspace() {
        guard let store, let recordID, letterArea != nil,
              let group = letterUndoGroups.popLast() else { return }
        for id in group.ids { try? store.deleteBlock(id) }
        letterCursor = Point(x: group.bounds.minX, y: group.lineTop)
        letterLineStartCount = (try? store.strokeBlocks(in: recordID).count) ?? 0
        drawingRewriteToken += 1
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
        letterUndoGroups = []
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
