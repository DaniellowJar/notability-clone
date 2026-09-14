import Foundation
import NotabilityCore
import SwiftUI

/// Shared application store. The database lives in the app sandbox's
/// Documents folder (survives app relaunches, backed up with the device).
@Observable
final class AppStore {
    static let shared = AppStore()

    let store: NotabilityStore
    var notebooks: [Notebook] = []

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dbURL = documents.appendingPathComponent("notability.sqlite")
        do {
            store = try NotabilityStore(path: dbURL.path)
        } catch {
            preconditionFailure("Unable to open Notability database at \(dbURL.path): \(error)")
        }
        refreshNotebooks()
    }

    // MARK: - Notebooks

    func createNotebook(title: String, coverColorHex: String) {
        guard !title.isEmpty else { return }
        do {
            _ = try store.createNotebook(title: title, coverColorHex: coverColorHex)
            refreshNotebooks()
        } catch {
            assertionFailure("createNotebook failed: \(error)")
        }
    }

    func renameNotebook(_ id: UUID, title: String) {
        guard !title.isEmpty else { return }
        do {
            try store.renameNotebook(id, title: title)
            refreshNotebooks()
        } catch {
            assertionFailure("renameNotebook failed: \(error)")
        }
    }

    func deleteNotebook(_ id: UUID) {
        do {
            try store.deleteNotebook(id)
            refreshNotebooks()
        } catch {
            assertionFailure("deleteNotebook failed: \(error)")
        }
    }

    func refreshNotebooks() {
        do {
            notebooks = try store.allNotebooks()
        } catch {
            notebooks = []
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