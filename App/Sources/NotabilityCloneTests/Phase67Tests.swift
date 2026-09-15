import NotabilityCore
import XCTest
@testable import NotabilityClone

final class Phase67Tests: XCTestCase {
    private var store: NotabilityStore!
    private var recordID: UUID!

    override func setUpWithError() throws {
        store = try NotabilityStore()
        let nb = try store.createNotebook(title: "NB", coverColorHex: "#000")
        recordID = try store.createRecord(in: nb.id, title: "r").id
    }

    func testInsertCalcBlockAndLocalEvaluate() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startPlaceCalc()
        session.place(intent: .calc, at: Point(x: 200, y: 200))
        XCTAssertEqual(session.blocks.count, 1)
        guard case .calc = session.blocks[0].payload else {
            return XCTFail("expected calc block")
        }

        let id = session.blocks[0].id
        session.setCalcExpression(id, expression: "300 x 2")
        XCTAssertEqual(session.blocks[0].calcResult, "600", "local evaluation must fill result")
        session.flushPendingSaves()

        let reloaded = CanvasSessionState()
        reloaded.load(recordID: recordID, store: store)
        XCTAssertEqual(reloaded.blocks[0].calcResult, "600", "result must persist")
    }

    func testCalcDefersComplexExpressionToAI() throws {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        session.startPlaceCalc()
        session.place(intent: .calc, at: Point(x: 200, y: 200))
        let id = session.blocks[0].id

        session.setCalcExpression(id, expression: "solve for x: 2x + 3 = 7")
        XCTAssertNil(session.evaluate("solve for x: 2x + 3 = 7"), "non-arithmetic needs AI")
        XCTAssertEqual(session.blocks[0].calcResult ?? "", "", "no local result for complex math")
    }

    func testLetterModeToggles() {
        let session = CanvasSessionState()
        session.load(recordID: recordID, store: store)
        XCTAssertFalse(session.letterMode)
        session.toggleLetterMode()
        XCTAssertTrue(session.letterMode)
    }

    func testStubMathOCRIsAvailableAndDeterministic() async throws {
        let result = try await AppProviders.shared.mathOCR.solve(imagePNG: Data([1]), recognizedText: "x^2")
        XCTAssertEqual(result.latex, "x^2")
    }
}
