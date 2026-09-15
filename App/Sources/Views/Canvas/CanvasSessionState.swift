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
    var letterMode = false

    private(set) var recordID: UUID?
    private(set) var store: NotabilityStore?

    private var marqueeStart: Point?
    private var pendingRef: String?
    private var pendingThumbRef: String?
    private var textSaveWorkItem: DispatchWorkItem?
    private var pendingText: (id: UUID, payload: BlockPayload)?
    private var pendingFrame: (id: UUID, frame: Rect)?

    // MARK: - Lifecycle

    func load(recordID: UUID, store: NotabilityStore) {
        self.recordID = recordID
        self.store = store
        reload()
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

    func toggleLetterMode() {
        letterMode.toggle()
    }

    func cancelTool() {
        mode = .draw
        marquee = nil
        marqueeStart = nil
        pendingRef = nil
        pendingThumbRef = nil
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
