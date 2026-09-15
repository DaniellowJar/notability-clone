import CryptoKit
import NotabilityCore
import PDFKit
import XCTest
@testable import NotabilityClone

final class Phase8_13Tests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testFileSecretsStoreRoundTripAndEncryptsAtRest() throws {
        let dir = tempDir()
        let store = FileSecretsStore(directory: dir, key: SymmetricKey(size: .bits256))

        XCTAssertNil(store.secret(for: "deepinfra"))
        try store.setSecret("sk-supersecret", for: "deepinfra")
        XCTAssertEqual(store.secret(for: "deepinfra"), "sk-supersecret")
        try store.deleteSecret(for: "deepinfra")
        XCTAssertNil(store.secret(for: "deepinfra"))

        let disk = try Data(contentsOf: dir.appendingPathComponent("secrets.bin"))
        XCTAssertFalse(disk.contains(Data("sk-supersecret".utf8)), "plaintext must never be written to disk")
        try? FileManager.default.removeItem(at: dir)
    }

    func testAppSecretsIsInjectable() throws {
        let dir = tempDir()
        let secrets = AppSecrets(store: FileSecretsStore(directory: dir, key: SymmetricKey(size: .bits256)))
        XCTAssertFalse(secrets.isConfigured)
        try secrets.saveDeepInfraKey("sk-test")
        XCTAssertEqual(secrets.deepInfraKey, "sk-test")
        XCTAssertTrue(secrets.isConfigured)
        try? FileManager.default.removeItem(at: dir)
    }

    func testPDFExtractCreatesBlob() throws {
        let tmp = tempDir()
        let url = tmp.appendingPathComponent("doc.pdf")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try makeTinyPDF().write(to: url)

        let ref = PDFExtractService.extractPage(pdfURL: url)
        XCTAssertNotNil(ref)
        if let ref {
            XCTAssertTrue(ref.hasPrefix("Media/PDF/"), "extract writes under Media/PDF")
            XCTAssertTrue(BlobStore.shared.exists(ref))
            XCTAssertNotNil(BlobStore.shared.data(for: ref))
        }
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeTinyPDF() throws -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            "Hello PDF".draw(at: CGPoint(x: 20, y: 20), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
    }
}
