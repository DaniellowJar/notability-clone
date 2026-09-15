import NotabilityCore
import SwiftUI

struct NotebookListView: View {
    @Environment(AppStore.self) private var app
    @State private var showingCreate = false
    @State private var errorMessage: String?
    @State private var path: [Route] = []
    @State private var pendingNotebookID: UUID?

    private let palette = ["#5B8DEF", "#F0A64A", "#7CC576", "#E06060", "#9B7EDE", "#4AC7C7"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: Self.gridColumns, spacing: 16) {
                    notebookGrid
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Notability")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addNotebook")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .notebook(let notebook):
                    NotebookPagesView(notebookID: notebook.id, path: $path)
                case .record(let record):
                    RecordCanvasView(record: record)
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateNotebookView(palette: palette) { title, color in
                    do {
                        let created = try app.createNotebook(title: title, coverColorHex: color)
                        // Push after the sheet is dismissed — NavigationStack drops
                        // path changes made while a sheet is still presented.
                        pendingNotebookID = created.notebook.id
                    } catch {
                        errorMessage = "Could not create notebook: \(error.localizedDescription)"
                    }
                }
            }
            .onChange(of: showingCreate) { _, dismissed in
                guard !dismissed, let nbID = pendingNotebookID else { return }
                pendingNotebookID = nil
                Task { @MainActor in
                    // Let the sheet finish dismissing before pushing — path
                    // changes during the dismissal transition get dropped.
                    try? await Task.sleep(for: .milliseconds(450))
                    if let notebook = app.notebooks.first(where: { $0.id == nbID }) {
                        path.append(.notebook(notebook))
                    }
                }
            }
            .alert("Error", isPresented: errorAlertBinding) {
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private static let gridColumns = [GridItem(.adaptive(minimum: 180), spacing: 16)]

    private var notebookGrid: some View {
        ForEach(app.notebooks) { notebook in
            NavigationLink(value: Route.notebook(notebook)) {
                NotebookCoverView(notebook: notebook)
            }
            .buttonStyle(.plain)
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

struct NotebookCoverView: View {
    let notebook: Notebook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: notebook.coverColorHex).opacity(0.85))
                .frame(height: 120)
                .overlay(alignment: .topLeading) {
                    Text(String(notebook.title.prefix(1)).uppercased())
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(12)
                }
            Text(notebook.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }
}

struct CreateNotebookView: View {
    @Environment(\.dismiss) private var dismiss
    let palette: [String]
    let onSave: (String, String) -> Void

    @State private var title = ""
    @State private var selectedColor = "#5B8DEF"

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Notebook name", text: $title)
                        .accessibilityIdentifier("notebookTitle")
                }
                Section("Cover color") {
                    HStack(spacing: 12) {
                        ForEach(palette, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 32, height: 32)
                                .overlay {
                                    if selectedColor == color {
                                        Circle().stroke(Color.accentColor, lineWidth: 3)
                                    }
                                }
                                .contentShape(Circle())
                                .onTapGesture { selectedColor = color }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New Notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onSave(title.trimmingCharacters(in: .whitespaces), selectedColor)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("createNotebook")
                }
            }
        }
        .presentationDetents([.medium])
    }
}