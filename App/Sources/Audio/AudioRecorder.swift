import AVFoundation
import Foundation
import NotabilityCore

/// Records 16 kHz mono 16-bit PCM WAV chunks (the format DeepInfra Whisper
/// accepts) with AVAudioRecorder. Each chunk calls `onChunkRecorded` with its
/// file URL and global start offset; `stop()` triggers `onStopped`.
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    static let chunkDuration: TimeInterval = 8
    static let sampleRate: Int = 16000

    var onChunkRecorded: ((URL, TimeInterval) -> Void)?
    var onStopped: (() -> Void)?

    private var recorder: AVAudioRecorder?
    private var chunkIndex = 0
    private var chunkURLs: [URL] = []

    private var chunksDir: URL {
        BlobStore.shared.url(for: BlobNaming.audioDir)
    }

    func start() -> Bool {
        try? FileManager.default.createDirectory(at: chunksDir, withIntermediateDirectories: true)
        chunkIndex = 0
        chunkURLs = []
        return recordNextChunk()
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        onStopped?()
    }

    private func recordNextChunk() -> Bool {
        let url = chunksDir.appendingPathComponent("chunk-\(chunkIndex).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            self.recorder = recorder
            return recorder.record(forDuration: Self.chunkDuration)
        } catch {
            return false
        }
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard flag else { return }
        chunkURLs.append(recorder.url)
        let startOffset = TimeInterval(chunkIndex) * Self.chunkDuration
        chunkIndex += 1
        onChunkRecorded?(recorder.url, startOffset)
        _ = recordNextChunk()
    }
}
