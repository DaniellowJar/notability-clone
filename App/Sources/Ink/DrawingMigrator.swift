import NotabilityCore
import PencilKit

/// Converts a legacy per-record PKDrawing blob into `.stroke` blocks so the
/// custom renderer owns the ink after Phase 3. Idempotent: only runs when a
/// blob exists AND the record has no stroke blocks yet. Runs in one pass.
enum DrawingMigrator {
    @discardableResult
    static func migrateIfNeeded(recordID: UUID, store: NotabilityStore, traits: UITraitCollection? = nil) -> Bool {
        guard let blob = try? store.drawingData(for: recordID) else { return false }
        guard let drawing = try? PKDrawing(data: blob) else { return false }
        let existing = (try? store.blocks(in: recordID)) ?? []
        guard !existing.contains(where: { $0.kind == .stroke }) else { return false }

        let resolved = traits ?? UITraitCollection.current
        let strokes = drawing.strokes.map { PKStrokeConverter.strokeData(from: $0, traits: resolved) }
        do {
            for stroke in strokes {
                _ = try store.addBlock(
                    in: recordID, kind: .stroke,
                    frame: stroke.bounds,
                    payload: .stroke([stroke], recognizedText: "", corrected: false)
                )
            }
            try store.clearDrawingData(for: recordID)
            return true
        } catch {
            return false
        }
    }
}
