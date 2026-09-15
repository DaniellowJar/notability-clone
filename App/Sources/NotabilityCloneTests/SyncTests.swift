import NotabilityCore
import XCTest
@testable import NotabilityClone

final class WebDAVParserTests: XCTestCase {
    func testParsesMultistatus() throws {
        let xml = """
        <?xml version="1.0"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/notability/backup.json</d:href>
            <d:propstat><d:prop>
              <d:getlastmodified>Mon, 15 Sep 2026 12:00:00 GMT</d:getlastmodified>
              <d:getetag>"abc123"</d:getetag>
            </d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """
        let files = try WebDAVParser.parseMultistatus(Data(xml.utf8))
        XCTAssertEqual(files.count, 1)
        guard let file = files.first else { return }
        XCTAssertEqual(file.path, "/notability/backup.json")
        XCTAssertEqual(file.etag, "\"abc123\"")
        XCTAssertNotNil(file.modifiedAt)
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try WebDAVParser.parseMultistatus(Data("not xml".utf8)))
    }
}
