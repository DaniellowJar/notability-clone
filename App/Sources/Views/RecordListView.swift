import NotabilityCore
import SwiftUI

struct RecordListView: View {
    let notebookID: UUID
    @Binding var path: [AnyHashable]

    @Environment(AppStore.self) private var app
    @State private var records: [Record] = []
    @State private var showingCreate = false
    @State private var newTitle = ""
    @State private var errorMessage: String?
    @State private var pendingCanvasRecord: Record?

    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink(value: record) {
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
                    do {
                        try app.store.deleteRecord(records[index].id)
                    } catch {
                        errorMessage = "Could not delete record: \(error.localizedDescription)"
                    }
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
                .accessibilityIdentifier("addRecord")
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                Form {
                    TextField("Record title", text: $newTitle)
                        .accessibilityIdentifier("recordTitle")
                }
                .navigationTitle("New Record")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCreate = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            createRecord()
                        }
                        .accessibilityIdentifier("createRecord")
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear(perform: reload)
        .onChange(of: showingCreate) { _, dismissed in
            if !dismissed, let record = pendingCanvasRecord {
                path.append(record)
                pendingCanvasRecord = nil
            }
        }
        .alert("Error", isPresented: errorAlertBinding) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var navigationTitle: String {
        guard let notebook = app.notebooks.first(where: { $0.id == notebookID }) else { return "Records" }
        return notebook.title
    }

    private func reload() {
        do {
            records = try app.store.records(in: notebookID)
        } catch {
            loggerError("reload failed", error)
            records = []
        }
    }

    private func createRecord() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        do {
            let record = try app.createRecord(in: notebookID, title: trimmed.isEmpty ? "Untitled" : trimmed)
            newTitle = ""
            reload()
            // Push after the sheet is dismissed — NavigationStack drops
            // path changes made while a sheet is still presented.
            pendingCanvasRecord = record
            showingCreate = false
        } catch {
            errorMessage = "Could not create record: \(error.localizedDescription)"
        }
    }

    private func loggerError(_ action: String, _ error: Error) {
        // Kept separate so reload() can never re-trigger a view update loop.
        #if DEBUG
        print("RecordListView: \(action): \(error)")
        #endif
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}