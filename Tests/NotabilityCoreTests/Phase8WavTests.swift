import XCTest
@testable import NotabilityCore

final class WavTests: XCTestCase {
    private func chunk(sampleRate: Int = 16000, payloadBytes: Int = 400) -> Data {
        var data = Wav.header(dataSize: payloadBytes, sampleRate: sampleRate)
        data.append(Data(repeating: 0, count: payloadBytes))
        return data
    }

    func testHeaderLengthAndMarkers() {
        let header = Wav.header(dataSize: 100)
        XCTAssertEqual(header.count, 44)
        XCTAssertTrue(header.starts(with: Array("RIFF".utf8)))
        XCTAssertEqual(String(decoding: header[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(String(decoding: header[36..<40], as: UTF8.self), "data")
    }

    func testSampleRateParsed() {
        XCTAssertEqual(Wav.sampleRate(of: chunk(sampleRate: 22050)), 22050)
        XCTAssertEqual(Wav.sampleRate(of: chunk()), 16000)
        XCTAssertEqual(Wav.sampleRate(of: Data([0, 1, 2])), 0)
    }

    func testPayloadRoundTrip() {
        let wav = chunk(payloadBytes: 100)
        XCTAssertEqual(Wav.payload(of: wav).count, 100)
        XCTAssertTrue(Wav.isWAV(wav))
    }

    func testConcatenateMergesPayloads() throws {
        let a = chunk(payloadBytes: 100)
        let b = chunk(payloadBytes: 200)
        let combined = try XCTUnwrap(WavConcatenator.concatenate([a, b]))
        XCTAssertEqual(Wav.payload(of: combined).count, 300)
        XCTAssertEqual(Wav.sampleRate(of: combined), 16000)
    }

    func testConcatenateRejectsMismatchedRates() {
        let a = chunk(sampleRate: 16000)
        let b = chunk(sampleRate: 44100)
        XCTAssertNil(WavConcatenator.concatenate([a, b]))
        XCTAssertNil(WavConcatenator.concatenate([]))
    }

    func testTotalDuration() {
        let a = chunk(payloadBytes: 320) // 160 samples at 16-bit mono
        let b = chunk(payloadBytes: 320)
        XCTAssertEqual(WavConcatenator.totalDuration(files: [a, b], sampleRate: 16000), 0.02, accuracy: 0.0001)
    }
}
