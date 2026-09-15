import NotabilityCore
import UIKit

/// Debounced background pipeline for Phase 4 + Phase 5:
/// after the user stops drawing, render each newly-written stroke block to an
/// image, run Vision recognition (accurate), store the recognized text, and
/// apply the geometric correction ("beautify v1") so the ink renders upright.
/// Runs off the main thread; the ink store is reloaded on main when done.
final class StrokeRecognitionService {
    let store: NotabilityStore
    let recordID: UUID
    private let inkStore: InkStrokeStore

    private var workItem: DispatchWorkItem?
    /// How many stroke blocks have recognized text (for debug/instrumentation).
    private(set) var recognizedCount = 0

    init(store: NotabilityStore, recordID: UUID, inkStore: InkStrokeStore) {
        self.store = store
        self.recordID = recordID
        self.inkStore = inkStore
    }

    /// Debounce: run recognition shortly after drawing pauses.
    func schedule(delay: TimeInterval = 1.5) {
        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.run()
        }
        workItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay, execute: work)
    }

    func runNow() {
        workItem?.cancel()
        run()
    }

    private func run() {
        guard let blocks = try? store.strokeBlocks(in: recordID) else { return }
        let pending = RecognitionPlan.pending(in: blocks)
        guard !pending.isEmpty else { return }

        var updated: [(UUID, BlockPayload)] = []
        for block in pending {
            guard case .stroke(let strokes, _, _) = block.payload,
                  let image = StrokeImageRenderer.render(strokes: strokes) else { continue }
            let text = VisionTextRecognizer.recognize(image: image) ?? ""
            guard !text.isEmpty else { continue }
            let correctedStrokes = strokes.map { StrokeCorrection.correct($0) }
            updated.append((block.id, RecognitionPlan.correctedStrokePayload(
                strokes: correctedStrokes, recognizedText: text
            )))
        }

        guard !updated.isEmpty else { return }
        do {
            for (id, payload) in updated {
                try store.updateBlockPayload(id, payload: payload)
            }
        } catch {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recognizedCount = self.updatedCount()
            self.reloadInk()
        }
    }

    private func updatedCount() -> Int {
        guard let blocks = try? store.strokeBlocks(in: recordID) else { return 0 }
        return RecognitionPlan.recognizedCount(in: blocks)
    }

    private func reloadInk() {
        guard let blocks = try? store.strokeBlocks(in: recordID) else { return }
        let strokes = blocks.compactMap { block -> StrokeData? in
            guard case .stroke(let list, _, _) = block.payload, let first = list.first else { return nil }
            return first
        }
        inkStore.load(strokes)
    }
}
