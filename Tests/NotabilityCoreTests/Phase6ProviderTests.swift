import XCTest
@testable import NotabilityCore

final class HexColorTests: XCTestCase {
    func testParseRGB() {
        XCTAssertEqual(HexColor.parse("#FF0000"), RGBColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(HexColor.parse("#0000FF"), RGBColor(red: 0, green: 0, blue: 1))
    }

    func testParseOptionalHashAndGarbage() {
        XCTAssertEqual(HexColor.parse("00FF00")?.green ?? 0, 1, accuracy: 0.0001)
        XCTAssertNil(HexColor.parse("nope"))
        XCTAssertNil(HexColor.parse("#FF"))
    }

    func testStringRoundTrips() {
        XCTAssertEqual(HexColor.string(HexColor.parse("#3366FF")!), "#3366FF")
    }

    func testLerp() {
        let mid = RGBColor.lerp(.black, .lightGray, t: 0.5)
        XCTAssertEqual(mid.red, 0.41, accuracy: 0.001)
        XCTAssertEqual(RGBColor.lerp(.black, .lightGray, t: 0), .black)
        XCTAssertEqual(RGBColor.lerp(.black, .lightGray, t: 1), .lightGray)
    }
}

final class LetterModeAgingTests: XCTestCase {
    func testAgeFractionOrdering() {
        XCTAssertEqual(LetterModeAging.ageFraction(strokeIndex: 4, total: 5), 0)
        XCTAssertEqual(LetterModeAging.ageFraction(strokeIndex: 0, total: 5), 1)
        XCTAssertEqual(LetterModeAging.ageFraction(strokeIndex: 0, total: 1), 0)
    }

    func testAlphaBounds() {
        XCTAssertEqual(LetterModeAging.alpha(ageFraction: 0), 1, accuracy: 0.001)
        XCTAssertEqual(LetterModeAging.alpha(ageFraction: 1), 0.15, accuracy: 0.001)
        XCTAssertEqual(LetterModeAging.alpha(ageFraction: 2), 0.15, accuracy: 0.001)
    }

    func testFadedColorNewestIsInk() {
        XCTAssertEqual(LetterModeAging.fadedColor(inkHex: "#FF0000", ageFraction: 0), "#FF0000")
    }

    func testFadedColorOldestIsLightGray() {
        XCTAssertEqual(LetterModeAging.fadedColor(inkHex: "#000000", ageFraction: 1), "#BCBCBC")
    }
}

final class ExpressionEvaluatorTests: XCTestCase {
    func testBasicArithmetic() throws {
        XCTAssertEqual(try ExpressionEvaluator.evaluate("300 x 2"), 600)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("300 × 2"), 600)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("10 ÷ 2"), 5)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("100 - 5 − 5"), 90)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("2 + 3 * 4"), 14)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("(2 + 3) * 4"), 20)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("3 * (4 + 5)"), 27)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("-5 + 3"), -2)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("2.5 * 2"), 5)
    }

    func testVariables() throws {
        XCTAssertEqual(try ExpressionEvaluator.evaluate("a + 3", variables: ["a": 10]), 13)
        XCTAssertEqual(try ExpressionEvaluator.evaluate("2 * b", variables: ["b": 4]), 8)
    }

    func testErrors() {
        XCTAssertThrowsError(try ExpressionEvaluator.evaluate("5 / 0")) { error in
            XCTAssertEqual(error as? ExpressionEvaluator.EvaluationError, .divisionByZero)
        }
        XCTAssertThrowsError(try ExpressionEvaluator.evaluate("")) { error in
            XCTAssertEqual(error as? ExpressionEvaluator.EvaluationError, .empty)
        }
        XCTAssertThrowsError(try ExpressionEvaluator.evaluate("1 +")) { error in
            guard case .unexpectedToken = error as? ExpressionEvaluator.EvaluationError else {
                return XCTFail("expected unexpectedToken")
            }
        }
        XCTAssertThrowsError(try ExpressionEvaluator.evaluate("q + 1")) { error in
            XCTAssertEqual(error as? ExpressionEvaluator.EvaluationError, .missingVariable("q"))
        }
    }
}

final class ProviderContractTests: XCTestCase {
    private let config = AIProviderConfig()

    func testMathOCRRequestShape() throws {
        let request = try ProviderRequestBuilders.mathOCR(imagePNG: Data([1, 2, 3]), recognizedText: "x^2 = 4", config: config)
        XCTAssertTrue(request.url.absoluteString.hasSuffix("/chat/completions"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.jsonBody) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, config.visionModel)
        let schema = try XCTUnwrap((json["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])
        XCTAssertEqual(schema["name"] as? String, "math_solution")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        // No API key in the request body or headers (transport injects it).
        XCTAssertFalse(request.jsonBody.description.contains("Bearer"))
        XCTAssertEqual(request.headers["Authorization"], nil)
    }

    func testTranscriptionRequestShape() throws {
        let request = try ProviderRequestBuilders.transcription(wav: Data([0, 0, 1]), language: "en", config: config)
        XCTAssertTrue(request.url.absoluteString.hasSuffix("/audio/transcriptions"))
        XCTAssertEqual(request.fields["model"], config.transcriptionModel)
        XCTAssertEqual(request.fields["response_format"], "verbose_json")
        XCTAssertEqual(request.fields["language"], "en")
        XCTAssertEqual(request.files["file"]?.filename, "chunk.wav")
        XCTAssertEqual(request.files["file"]?.contentType, "audio/wav")
    }

    func testQuizRequestShape() throws {
        let request = try ProviderRequestBuilders.quiz(transcript: "t", notes: "n", config: config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.jsonBody) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, config.chatModel)
        let schema = try XCTUnwrap((json["response_format"] as? [String: Any])?["json_schema"] as? [String: Any])
        XCTAssertEqual(schema["name"] as? String, "quiz")
    }

    func testBackgroundRemovalRequiresConfiguredBaseURL() {
        XCTAssertThrowsError(try ProviderRequestBuilders.backgroundRemoval(imagePNG: Data([1]), config: AIProviderConfig())) { error in
            XCTAssertEqual(error as? AIProviderError, .notConfigured)
        }
        var configured = AIProviderConfig()
        configured.backgroundRemovalBaseURL = "https://shim.example.com"
        let request = try? ProviderRequestBuilders.backgroundRemoval(imagePNG: Data([1]), config: configured)
        XCTAssertEqual(request?.files["image"]?.contentType, "image/png")
    }

    func testMathOCRParser() throws {
        let fixture = """
        {"choices":[{"message":{"content":"{\\"latex\\":\\"x^2\\",\\"expression\\":\\"x*x\\",\\"result\\":\\"\\",\\"steps\\":[\\"factor\\"],\\"variables\\":{\\"a\\":2.0}}"}}]}
        """
        let result = try ProviderParsers.mathOCR(Data(fixture.utf8))
        XCTAssertEqual(result.latex, "x^2")
        XCTAssertEqual(result.variables["a"], 2)
    }

    func testTranscriptionParser() throws {
        let fixture = """
        {"task":"transcribe","language":"en","duration":8.0,"text":"first second",
         "segments":[{"id":0,"start":0.0,"end":3.4,"text":"first"},{"id":1,"start":3.4,"end":8.0,"text":"second"}]}
        """
        let result = try ProviderParsers.transcription(Data(fixture.utf8))
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].text, "first")
        XCTAssertEqual(result.fullText, "first second")
    }

    func testQuizParser() throws {
        let fixture = """
        {"choices":[{"message":{"content":"{\\"questions\\":[{\\"question\\":\\"q\\",\\"choices\\":[\\"a\\",\\"b\\"],\\"answerIndex\\":0,\\"explanation\\":\\"e\\"}]}"}}]}
        """
        let quiz = try ProviderParsers.quiz(Data(fixture.utf8))
        XCTAssertEqual(quiz.questions.count, 1)
        XCTAssertEqual(quiz.questions[0].answerIndex, 0)
    }

    func testBackgroundRemovalParser() throws {
        let b64 = Data([137, 80, 78, 71]).base64EncodedString()
        let fixture = #"{"created":0,"data":[{"b64_json":"\#(b64)"}]}"#
        let png = try ProviderParsers.backgroundRemoval(Data(fixture.utf8))
        XCTAssertEqual(png, Data([137, 80, 78, 71]))
    }

    func testStubProvidersAreDeterministic() async throws {
        let quiz = try await StubQuizProvider().generateQuiz(transcript: "x", notes: "y")
        XCTAssertEqual(quiz.questions.count, 3)
        let bg = try await StubBackgroundRemovalProvider().removeBackground(imagePNG: Data([1]))
        XCTAssertEqual(bg, Data([1]))
    }
}
