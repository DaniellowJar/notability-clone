import Foundation
import NotabilityCore
import os
import SwiftUI

/// Shared application store. The database lives in the app sandbox's
/// Documents folder (survives app relaunches, backed up with the device).
@Observable
final class AppStore {
    static let shared = AppStore()

    let store: NotabilityStore
    var notebooks: [Notebook] = []

    private let logger = Logger(subsystem: "com.daniellow.notabilityclone", category: "AppStore")

    private init() {
        // UI tests (XCUITest) launch with -inMemoryStore for a clean, isolated
        // database each run; normal launches use the sandboxed Documents file.
        if ProcessInfo.processInfo.arguments.contains("-inMemoryStore") {
            AppSettings.shared.resetForTesting()
            do {
                store = try NotabilityStore()
            } catch {
                preconditionFailure("Unable to open in-memory Notability database: \(error)")
            }
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dbURL = documents.appendingPathComponent("notability.sqlite")
            do {
                store = try NotabilityStore(path: dbURL.path)
            } catch {
                preconditionFailure("Unable to open Notability database at \(dbURL.path): \(error)")
            }
            importSeedIfPresent(in: documents)
        }
        refreshNotebooks()
    }

    // MARK: - Notebooks

    /// Creates the notebook only — no auto-created page. The user lands on an
    /// empty Pages screen and adds pages themselves ("Page N"). Throws so the
    /// caller can surface the error.
    func createNotebook(title: String, coverColorHex: String) throws -> Notebook {
        let created = try store.createNotebook(title: title, coverColorHex: coverColorHex)
        refreshNotebooks()
        return created
    }

    func createRecord(in notebookID: UUID, title: String) throws -> Record {
        try store.createRecord(in: notebookID, title: title)
    }

    func renameNotebook(_ id: UUID, title: String) {
        guard !title.isEmpty else { return }
        do {
            try store.renameNotebook(id, title: title)
            refreshNotebooks()
        } catch {
            logger.error("renameNotebook failed: \(String(describing: error))")
        }
    }

    func deleteNotebook(_ id: UUID) {
        do {
            try store.deleteNotebook(id)
            refreshNotebooks()
        } catch {
            logger.error("deleteNotebook failed: \(String(describing: error))")
        }
    }

    func refreshNotebooks() {
        do {
            notebooks = try store.allNotebooks()
        } catch {
            logger.error("refreshNotebooks failed: \(String(describing: error))")
            notebooks = []
        }
    }

    // MARK: - LiveContainer / seed JSON

    /// LiveContainer plug-in: drop `notability-seed.json` into the app's
    /// Documents folder and it is imported on the next launch. Idempotent —
    /// existing ids are skipped, so keeping the file around is safe.
    private func importSeedIfPresent(in documents: URL) {
        let url = documents.appendingPathComponent("notability-seed.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let summary = try store.importBackup(data)
            logger.info("Imported notability-seed.json: \(summary.total) rows")
        } catch {
            logger.error("Seed import failed: \(String(describing: error))")
        }
    }
}

extension Color {
    /// Parses "#RRGGBB" / "#RRGGBBAA". Falls back to gray.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let int = UInt64(value, radix: 16) else {
            self = .gray
            return
        }
        let r: Double, g: Double, b: Double, a: Double
        if value.count == 8 {
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8) & 0xFF) / 255
            a = Double(int & 0xFF) / 255
        } else {
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}