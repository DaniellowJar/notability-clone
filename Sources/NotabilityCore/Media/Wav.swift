import Foundation

/// Canonical 16-bit PCM mono WAV (the format DeepInfra Whisper accepts).
/// Kept pure so chunk concatenation is Linux-testable.
public enum Wav {
    public static let headerLength = 44
    public static let defaultSampleRate = 16000

    /// Builds a 44-byte PCM WAV header for a payload of `dataSize` bytes.
    public static func header(dataSize: Int, sampleRate: Int = Wav.defaultSampleRate, channels: Int = 1) -> Data {
        let byteRate = sampleRate * channels * 2
        let blockAlign = channels * 2
        var data = Data()
        data.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(&data, UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(&data, 16)
        appendUInt16(&data, 1) // PCM
        appendUInt16(&data, UInt16(channels))
        appendUInt32(&data, UInt32(sampleRate))
        appendUInt32(&data, UInt32(byteRate))
        appendUInt16(&data, UInt16(blockAlign))
        appendUInt16(&data, 16) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        appendUInt32(&data, UInt32(dataSize))
        return data
    }

    /// Payload (samples) after the 44-byte header.
    public static func payload(of wav: Data) -> Data {
        guard wav.count > headerLength else { return Data() }
        return wav.subdata(in: headerLength..<wav.count)
    }

    /// Sample rate read from the header (0 if not a PCM WAV).
    public static func sampleRate(of wav: Data) -> Int {
        guard wav.count >= headerLength, wav.starts(with: Array("RIFF".utf8)) else { return 0 }
        // sampleRate at offset 24 (little-endian UInt32)
        return Int(readUInt32(wav, at: 24))
    }

    public static func isWAV(_ data: Data) -> Bool {
        data.count >= 4 && data.starts(with: Array("RIFF".utf8))
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let b0 = UInt32(data[data.index(data.startIndex, offsetBy: offset)])
        let b1 = UInt32(data[data.index(data.startIndex, offsetBy: offset + 1)]) << 8
        let b2 = UInt32(data[data.index(data.startIndex, offsetBy: offset + 2)]) << 16
        let b3 = UInt32(data[data.index(data.startIndex, offsetBy: offset + 3)]) << 24
        return b0 | b1 | b2 | b3
    }
}

/// Merges recorded 16-bit PCM WAV chunks into a single audio track.
public enum WavConcatenator {
    /// Returns a single WAV whose payload is the concatenation of `files`.
    /// Returns nil if any file isn't a valid WAV.
    public static func concatenate(_ files: [Data]) -> Data? {
        guard !files.isEmpty else { return nil }
        let rate = Wav.sampleRate(of: files[0])
        guard rate > 0 else { return nil }
        var payloads: [Data] = []
        for file in files {
            guard Wav.sampleRate(of: file) == rate else { return nil }
            payloads.append(Wav.payload(of: file))
        }
        let combined = payloads.reduce(Data(), +)
        return Wav.header(dataSize: combined.count, sampleRate: rate) + combined
    }

    public static func totalDuration(files: [Data], sampleRate: Int = Wav.defaultSampleRate) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        let totalSamples = files.reduce(0) { $0 + Wav.payload(of: $1).count / 2 }
        return TimeInterval(totalSamples) / TimeInterval(sampleRate)
    }
}
