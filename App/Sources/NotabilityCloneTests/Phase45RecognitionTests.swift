import NotabilityCore
import UIKit
import XCTest
@testable import NotabilityClone

final class Phase45RecognitionTests: XCTestCase {
    func testVisionRecognizesRenderedText() throws {
        // Render a crisp word to an image, then confirm accurate-mode Vision
        // reads it back. Exercises the same image → text path used on ink.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 120))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 120))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("HELLO" as NSString).draw(at: CGPoint(x: 40, y: 30), withAttributes: attrs)
        }

        let text = VisionTextRecognizer.recognize(image: image)
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.uppercased().contains("HELLO") == true,
                      "recognized text was: \(text ?? "nil")")
    }

    func testCorrectionPersistedInPayload() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        let leaning = StrokeData(
            points: (0..<5).map { i in
                StrokePoint(location: Point(x: 2 - Double(i) * 0.3, y: Double(i) * 5),
                            timestampOffset: Double(i) * 0.01, width: 2, force: 1, azimuth: 0, altitude: 45)
            },
            colorHex: "#000", baseWidth: 2
        )
        let block = try store.addBlock(in: rec.id, kind: .stroke, frame: leaning.bounds,
                                       payload: .stroke([leaning], recognizedText: "", corrected: false))

        let corrected = StrokeCorrection.correct(leaning)
        let payload = RecognitionPlan.correctedStrokePayload(strokes: [corrected], recognizedText: "hi")
        try store.updateBlockPayload(block.id, payload: payload)

        let stored = try store.block(id: block.id)
        guard case .stroke(let strokes, let text, let flag) = stored?.payload else {
            return XCTFail("expected stroke payload")
        }
        XCTAssertEqual(text, "hi")
        XCTAssertTrue(flag)
        XCTAssertNotNil(strokes.first?.correctedPoints, "corrected points must persist")
    }
}
