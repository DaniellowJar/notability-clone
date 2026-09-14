import XCTest
import NotabilityCore

final class AppSmokeTests: XCTestCase {
    func testInMemoryStoreWorksInProcess() throws {
        let store = try NotabilityStore()
        let nb = try store.createNotebook(title: "Smoke", coverColorHex: "#000")
        let rec = try store.createRecord(in: nb.id, title: "r")
        let block = try store.addBlock(in: rec.id, kind: .calc, frame: .zero, payload: .calc(CalcBlockPayload(expression: "1+1")))
        XCTAssertEqual(try store.blocks(in: rec.id).first?.id, block.id)
        XCTAssertEqual(block.kind, .calc)
    }
}