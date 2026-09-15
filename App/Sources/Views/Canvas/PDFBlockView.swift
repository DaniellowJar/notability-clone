import NotabilityCore
import PDFKit
import SwiftUI

/// A PDF attachment block: a page-0 thumbnail card that opens the read-only
/// PDFKit viewer when tapped.
struct PDFBlockView: View {
    let block: CanvasBlock

    @State private var thumb: UIImage?
    @State private var showReader = false

    var body: some View {
        Group {
            if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    VStack(spacing: 6) {
                        Image(systemName: "doc")
                            .font(.system(size: 28))
                        Text("PDF")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: block.frame.size.width, height: block.frame.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onAppear(perform: load)
        .onTapGesture { showReader = true }
        .sheet(isPresented: $showReader) {
            if let url = pdfURL {
                PDFKitReaderView(url: url)
            }
        }
    }

    private var pdfURL: URL? {
        block.pdfSourceRef.map { BlobStore.shared.url(for: $0) }
    }

    private func load() {
        guard thumb == nil, let thumbRef = block.pdfThumbRef else { return }
        thumb = BlobStore.shared.data(for: thumbRef).flatMap(UIImage.init(data:))
    }
}

/// Read-only PDFKit attachment viewer (extract mode is Phase 10).
struct PDFKitReaderView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFKitView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.deletingPathExtension().lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
