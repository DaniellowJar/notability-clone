import Foundation

/// Blob storage under the app's Documents/Media tree. `fileRef` values are
/// relative paths from Documents (see `BlobNaming`) so backups and Phase 11
/// WebDAV can mirror a stable tree.
final class BlobStore {
    static let shared = BlobStore()

    /// Base directory; defaults to Documents. Injectable for tests.
    let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func url(for ref: String) -> URL {
        root.appendingPathComponent(ref)
    }

    @discardableResult
    func save(_ data: Data, as ref: String) throws -> URL {
        let url = url(for: ref)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    func data(for ref: String) -> Data? {
        try? Data(contentsOf: url(for: ref))
    }

    func exists(_ ref: String) -> Bool {
        fm.fileExists(atPath: url(for: ref).path)
    }

    func delete(_ ref: String) {
        try? fm.removeItem(at: url(for: ref))
    }

    /// Deletes blobs only when no other block references them.
    func deleteIfUnreferenced(refs: [String], among blocks: [CanvasBlock]) {
        let used: Set<String> = Set(blocks.flatMap { BlockPayload.references(in: $0) })
        for ref in refs where !used.contains(ref) {
            delete(ref)
        }
    }
}

extension BlockPayload {
    /// Media refs a block points at, for blob lifecycle management.
    static func references(in block: CanvasBlock) -> [String] {
        switch block.payload {
        case .image(let p): [p.imageRef]
        case .pdfPage(let p): [p.sourcePDFRef, p.renderedImageRef].compactMap { $0.isEmpty ? nil : $0 }
        default: []
        }
    }
}
