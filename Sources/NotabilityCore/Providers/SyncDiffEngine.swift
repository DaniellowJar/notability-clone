import Foundation

/// WebDAV/OwnCloud sync (Phase 11): last-write-wins per block on `modifiedAt`.
/// Pure planning: given local entries and a remote PROPFIND listing, compute
/// upload/download operations. Deletion propagation needs a change log
/// (tombstones) and is out of scope for v1 — noted in PHASES.md.
public struct LocalEntry: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date

    public init(path: String, modifiedAt: Date) {
        self.path = path
        self.modifiedAt = modifiedAt
    }
}

public struct RemoteFile: Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let etag: String?

    public init(path: String, modifiedAt: Date, etag: String? = nil) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.etag = etag
    }
}

public enum SyncOp: Equatable, Sendable {
    case upload(path: String)
    case download(path: String)
}

public struct SyncDiff: Equatable, Sendable {
    public let ops: [SyncOp]

    public init(ops: [SyncOp]) {
        self.ops = ops
    }

    public var isEmpty: Bool { ops.isEmpty }
}

public enum SyncDiffEngine {
    /// Compares local state against the remote listing. A file missing on one
    /// side is uploaded/downloaded; when both exist, the newer mtime wins.
    public static func plan(local: [LocalEntry], remote: [RemoteFile]) -> SyncDiff {
        let localByPath = Dictionary(uniqueKeysWithValues: local.map { ($0.path, $0) })
        let remoteByPath = Dictionary(uniqueKeysWithValues: remote.map { ($0.path, $0) })

        var ops: [SyncOp] = []
        let allPaths = Set(localByPath.keys).union(remoteByPath.keys)

        for path in allPaths.sorted() {
            switch (localByPath[path], remoteByPath[path]) {
            case (.some, nil):
                ops.append(.upload(path: path))
            case (nil, .some):
                ops.append(.download(path: path))
            case let (.some(localFile), .some(remoteFile)):
                if localFile.modifiedAt > remoteFile.modifiedAt {
                    ops.append(.upload(path: path))
                } else if remoteFile.modifiedAt > localFile.modifiedAt {
                    ops.append(.download(path: path))
                }
            case (nil, nil):
                break
            }
        }
        return SyncDiff(ops: ops)
    }
}
