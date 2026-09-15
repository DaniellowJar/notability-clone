import Foundation

/// Pure bookkeeping for background handwriting recognition (Phase 4):
/// which stroke blocks still need OCR, and how recognized text is merged back
/// into their payloads. The Vision call itself is app-side.
public enum RecognitionPlan {
    /// Stroke blocks whose recognized text is still empty — candidates for OCR.
    public static func pending(in blocks: [CanvasBlock]) -> [CanvasBlock] {
        blocks.filter { block in
            guard case .stroke(_, let text, _) = block.payload else { return false }
            return text.isEmpty
        }
    }

    public static func recognizedCount(in blocks: [CanvasBlock]) -> Int {
        blocks.reduce(0) { count, block in
            guard case .stroke(_, let text, _) = block.payload, !text.isEmpty else { return count }
            return count + 1
        }
    }

    /// Returns `block` with its stroke payload's recognized text replaced.
    public static func withRecognizedText(_ text: String, on block: CanvasBlock) -> CanvasBlock {
        guard case .stroke(let strokes, _, let corrected) = block.payload else { return block }
        return replacing(.stroke(strokes, recognizedText: text, corrected: corrected), on: block)
    }

    /// Returns `block` with its corrected flag set (beautification applied).
    public static func withCorrected(_ corrected: Bool, on block: CanvasBlock) -> CanvasBlock {
        guard case .stroke(let strokes, let text, _) = block.payload else { return block }
        return replacing(.stroke(strokes, recognizedText: text, corrected: corrected), on: block)
    }

    /// Payload for a stroke block after the correction pass: corrected strokes,
    /// recognized text, and `corrected = true`.
    public static func correctedStrokePayload(strokes: [StrokeData], recognizedText: String) -> BlockPayload {
        .stroke(strokes, recognizedText: recognizedText, corrected: true)
    }

    private static func replacing(_ payload: BlockPayload, on block: CanvasBlock) -> CanvasBlock {
        CanvasBlock(
            id: block.id, recordId: block.recordId, kind: block.kind,
            frame: block.frame, zIndex: block.zIndex, timestamp: block.timestamp,
            payload: payload, modifiedAt: block.modifiedAt
        )
    }
}
