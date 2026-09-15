import NotabilityCore
import Foundation

/// Phase 11: OwnCloud/WebDAV sync. v1 syncs the full store backup snapshot
/// (`backup.json`) plus the Media blob tree, last-write-wins on mtime via the
/// core `SyncDiffEngine`. Deletion propagation (tombstones) is out of scope v1.
final class SyncService {
    static let rootPath = "notability"
    static let backupPath = "notability/backup.json"

    let store: NotabilityStore

    init(store: NotabilityStore) {
        self.store = store
    }

    var isConfigured: Bool {
        AppSecrets.shared.ownCloudURL != nil
    }

    private var client: WebDAVClient? {
        let secrets = AppSecrets.shared
        guard let urlString = secrets.ownCloudURL, let url = URL(string: urlString),
              let user = secrets.ownCloudUser, let password = secrets.ownCloudPassword else { return nil }
        return WebDAVClient(baseURL: url, username: user, password: password)
    }

    /// Runs one LWW sync pass. Throws `.notConfigured` when no OwnCloud
    /// credentials are stored (Settings).
    func sync() async throws {
        guard let client else { throw AIProviderError.notConfigured }
        let remote = try await client.list(path: Self.rootPath)
        let local = buildLocalEntries()
        let diff = SyncDiffEngine.plan(local: local, remote: remote)
        for op in diff.ops {
            switch op {
            case .upload(let path):
                let data = try dataForLocal(path: path)
                try await client.upload(path: path, data: data)
            case .download(let path):
                let data = try await client.download(path: path)
                try applyRemote(path: path, data: data)
            }
        }
    }

    // MARK: - Local entries

    private func buildLocalEntries() -> [LocalEntry] {
        var entries = [LocalEntry(path: Self.backupPath, modifiedAt: store.latestModifiedAt())]
        let mediaRoot = BlobStore.shared.url(for: BlobNaming.mediaRoot)
        let fm = FileManager.default
        if let enumerator = fm.enumerator(at: mediaRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.hasDirectoryPath == false {
                guard let rel = url.path.split(separator: "/").dropFirst(mediaRoot.pathComponents.count).joined(separator: "/").removingPercentEncoding else { continue }
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                entries.append(LocalEntry(path: "\(Self.rootPath)/Media/\(rel)", modifiedAt: mtime))
            }
        }
        return entries
    }

    private func dataForLocal(path: String) throws -> Data {
        if path == Self.backupPath {
            return try store.backupData()
        }
        // Media/<...> → blob ref relative to Documents
        let prefix = "\(Self.rootPath)/Media/"
        guard path.hasPrefix(prefix) else { throw AIProviderError.invalidResponse }
        let ref = "\(BlobNaming.mediaRoot)/\(path.dropFirst(prefix.count))"
        guard let data = BlobStore.shared.data(for: ref) else { throw AIProviderError.invalidResponse }
        return data
    }

    private func applyRemote(path: String, data: Data) throws {
        if path == Self.backupPath {
            _ = try store.importBackup(data)
            return
        }
        let prefix = "\(Self.rootPath)/Media/"
        guard path.hasPrefix(prefix) else { throw AIProviderError.invalidResponse }
        let ref = "\(BlobNaming.mediaRoot)/\(path.dropFirst(prefix.count))"
        try BlobStore.shared.save(data, as: ref)
    }
}
