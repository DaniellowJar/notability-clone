import NotabilityCore
import Foundation

/// Coordinates audio capture → transcription → store for one Record (Phase 8).
/// Chunks are recorded in WAV, transcribed via the (stub by default) provider,
/// and segment times are offset by each chunk's global start so the shared
/// clock aligns with canvas block timestamps.
final class RecordingSession {
    let store: NotabilityStore
    let recordID: UUID

    private let recorder = AudioRecorder()
    private let provider: TranscriptionProviding = AppProviders.shared.transcription
    private var startDate: Date?
    private var chunkData: [Data] = []

    private(set) var isRecording = false
    var onTranscriptUpdate: (() -> Void)?
    var onError: ((String) -> Void)?

    init(store: NotabilityStore, recordID: UUID) {
        self.store = store
        self.recordID = recordID
    }

    func start() {
        guard !isRecording else { return }
        startDate = Date()
        chunkData = []
        recorder.onChunkRecorded = { [weak self] url, offset in
            self?.handleChunk(url: url, offset: offset)
        }
        recorder.onStopped = { [weak self] in
            self?.finalize()
        }
        guard recorder.start() else {
            onError?("Could not start recording. Check microphone permission.")
            return
        }
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        recorder.stop()
        isRecording = false
    }

    private func handleChunk(url: URL, offset: TimeInterval) {
        guard let data = try? Data(contentsOf: url) else { return }
        chunkData.append(data)
        Task {
            // TODO(provider): stub by default; swap for live DeepInfra Whisper
            // once an API key is stored (Phase 13 Settings).
            let result = try? await provider.transcribe(wav: data, language: nil)
            await MainActor.run {
                guard let result else { return }
                let baseSeq = (try? store.transcript(for: recordID).segments.count) ?? 0
                for (i, segment) in result.segments.enumerated() {
                    try? store.appendTranscriptSegment(TranscriptSegment(
                        recordId: recordID, seq: baseSeq + i,
                        text: segment.text,
                        startTime: offset + segment.start,
                        endTime: offset + segment.end
                    ))
                }
                onTranscriptUpdate?()
            }
        }
    }

    private func finalize() {
        guard let startDate, !chunkData.isEmpty,
              let combined = WavConcatenator.concatenate(chunkData) else { return }
        let ref = BlobNaming.audioRef()
        do {
            try BlobStore.shared.save(combined, as: ref)
            let duration = WavConcatenator.totalDuration(files: chunkData, sampleRate: AudioRecorder.sampleRate)
            try store.setAudioTrack(AudioTrack(fileRef: ref, duration: duration, recordedAt: startDate), for: recordID)
        } catch {
            onError?("Could not save recording: \(error.localizedDescription)")
        }
    }
}
