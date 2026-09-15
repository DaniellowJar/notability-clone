import NotabilityCore
import SwiftUI

/// The "Pages" screen for a notebook: the record model is presented as
/// pages. A prominent inline "New Page" button (plus a redundant toolbar
/// shortcut) always gives a visible way to create, and tapping a page opens
/// its canvas. Creating a page goes straight to the canvas in one tap.
struct NotebookPagesView: View {
    let notebookID: UUID
    @Binding var path: [Route]

    @Environment(AppStore.self) private var app
    @State private var pages: [Record] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button(action: createAndOpenPage) {
                    Label("New Page", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("addPage")
            }
            Section("Pages") {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, record in
                    NavigationLink(value: Route.record(record)) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(record.title)
                                    .font(.body)
                                Text("Page \(index + 1) · \(record.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        do {
                            try app.store.deleteRecord(pages[index].id)
                        } catch {
                            errorMessage = "Could not delete page: \(error.localizedDescription)"
                        }
                    }
                    reload()
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createAndOpenPage) {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("addPageToolbar")
            }
        }
        .onAppear(perform: reload)
        #if DEBUG
        .safeAreaInset(edge: .top) {
            Text("pages=\(pages.count) nb=\(notebookID.uuidString)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("pagesDebug")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        #endif
        .alert("Error", isPresented: errorAlertBinding) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var navigationTitle: String {
        guard let notebook = app.notebooks.first(where: { $0.id == notebookID }) else { return "Pages" }
        return notebook.title
    }

    private func reload() {
        do {
            pages = try app.store.records(in: notebookID)
        } catch {
            // Never fail silently — an empty list hides real storage errors.
            errorMessage = "Could not load pages: \(error.localizedDescription)"
        }
    }

    /// One tap: create a page and open its canvas.
    private func createAndOpenPage() {
        do {
            let record = try app.createRecord(in: notebookID, title: "Page \(pages.count + 1)")
            pages = try app.store.records(in: notebookID)
            path.append(.record(record))
        } catch {
            errorMessage = "Could not create page: \(error.localizedDescription)"
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
