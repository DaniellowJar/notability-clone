import UIKit
import Vision

/// On-device handwriting/text recognition (accurate mode). Runs synchronously —
/// call on a background queue.
enum VisionTextRecognizer {
    static func recognize(image: UIImage, languageCorrection: Bool = true) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = languageCorrection
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
    }
}
