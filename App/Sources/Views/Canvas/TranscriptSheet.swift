import NotabilityCore
import SwiftUI

/// Phase 9 transcript UI: ordered segments; tapping one uses the shared clock
/// to reveal which canvas blocks were written in that window (click-to-sync).
struct TranscriptSheet: View {
    let store: NotabilityStore
    let recordID: UUID
    let blocks: [CanvasBlock]

    @Environment(\.dismiss) private var dismiss
    @State private var transcript = Transcript(segments: [])
    @State private var recordingStart: Date?
    @State private var selectedBlocks: [CanvasBlock] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(transcript.segments, id: \.id) { segment in
                    Button {
                        select(segment)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.text)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Text("\(time(segment.startTime)) – \(time(segment.endTime))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedBlocks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Blocks written in this window: \(selectedBlocks.count)")
                            .font(.footnote)
                            .fontWeight(.semibold)
                        ForEach(selectedBlocks.prefix(6)) { block in
                            Text(blockTitle(block))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        transcript = (try? store.transcript(for: recordID)) ?? Transcript(segments: [])
        recordingStart = (try? store.audioTrack(for: recordID))?.recordedAt
    }

    private func select(_ segment: TranscriptSegment) {
        guard let recordingStart else {
            selectedBlocks = []
            return
        }
        selectedBlocks = TimelineSync.blocks(
            blocks,
            overlapping: segment.startTime,
            endOffset: segment.endTime,
            recordingStart: recordingStart
        )
    }

    private func blockTitle(_ block: CanvasBlock) -> String {
        switch block.payload {
        case .text(let p): return p.text.isEmpty ? "Text block" : p.text
        case .calc(let p): return p.expression
        case .stroke: return "Handwriting"
        default: return block.kind.title
        }
    }

    private func time(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
