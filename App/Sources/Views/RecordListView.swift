import NotabilityCore
import SwiftUI

struct RecordListView: View {
    let notebookID: UUID

    @Environment(AppStore.self) private var app
    @State private var records: [Record] = []
    @State private var showingCreate = false
    @State private var newTitle = ""

    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink(value: record.id) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(record.title)
                                .font(.body)
                            Text(record.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    try? app.store.deleteRecord(records[index].id)
                }
                reload()
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(for: UUID.self) { recordID in
            RecordCanvasView(recordID: recordID)
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                Form {
                    TextField("Record title", text: $newTitle)
                }
                .navigationTitle("New Record")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            let title = newTitle.trimmingCharacters(in: .whitespaces)
                            _ = try? app.store.createRecord(in: notebookID, title: title.isEmpty ? "Untitled" : title)
                            newTitle = ""
                            showingCreate = false
                            reload()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear(perform: reload)
    }

    private var navigationTitle: String {
        guard let notebook = app.notebooks.first(where: { $0.id == notebookID }) else { return "Records" }
        return notebook.title
    }

    private func reload() {
        do {
            records = try app.store.records(in: notebookID)
        } catch {
            records = []
        }
    }
}