import Foundation
import NotabilityCore

/// Minimal WebDAV client (PROPFIND/GET/PUT/DELETE) for OwnCloud sync (Phase 11).
/// Credentials come from the Keychain via `AppSecrets` — never stored here.
struct WebDAVClient {
    let baseURL: URL
    let username: String
    let password: String
    private let session: URLSession

    init(baseURL: URL, username: String, password: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.session = session
    }

    private var authHeader: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    func list(path: String) async throws -> [RemoteFile] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw AIProviderError.statusCode(http.statusCode) }
        return try WebDAVParser.parseMultistatus(data)
    }

    func download(path: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIProviderError.statusCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func upload(path: String, data: Data) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIProviderError.statusCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func delete(path: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AIProviderError.statusCode((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }
}

/// Parses a WebDAV multistatus response (XML) into `RemoteFile`s.
enum WebDAVParser {
    static func parseMultistatus(_ data: Data) throws -> [RemoteFile] {
        let parser = ParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { throw AIProviderError.invalidResponse }
        return parser.files
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var files: [RemoteFile] = []
        private var currentHref: String?
        private var currentMtime: Date?
        private var currentEtag: String?
        private var textBuffer = ""

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            textBuffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            textBuffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "href":
                currentHref = trimmed
            case "getlastmodified":
                currentMtime = Self.parseDate(trimmed)
            case "getetag":
                currentEtag = trimmed
            case "response":
                if let href = currentHref, let mtime = currentMtime {
                    files.append(RemoteFile(path: href, modifiedAt: mtime, etag: currentEtag))
                }
                currentHref = nil
                currentMtime = nil
                currentEtag = nil
            default:
                break
            }
            textBuffer = ""
        }

        private static func parseDate(_ string: String) -> Date? {
            for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                if let date = formatter.date(from: string) { return date }
            }
            return nil
        }
    }
}
