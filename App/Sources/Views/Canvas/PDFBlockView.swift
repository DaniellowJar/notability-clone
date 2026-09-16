import NotabilityCore
import PDFKit
import SwiftUI

/// A PDF attachment block: the vector page rendered live at the current zoom,
/// opening the read-only PDFKit viewer when tapped.
struct PDFBlockView: View {
    let block: CanvasBlock
    let zoomScale: Double

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var thumb: UIImage?
    @State private var renderEpoch = 0
    @State private var renderWork: DispatchWorkItem?
    @State private var showReader = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let thumb {
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
        .onAppear {
            loadThumb()
            scheduleRender()
        }
        .onChange(of: zoomScale) { scheduleRender() }
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

    private func loadThumb() {
        guard thumb == nil, let thumbRef = block.pdfThumbRef else { return }
        thumb = BlobStore.shared.data(for: thumbRef).flatMap(UIImage.init(data:))
    }

    /// Re-render at the settled zoom (debounced so a continuous pinch doesn't
    /// rasterize every frame). Stale renders never apply thanks to the epoch.
    private func scheduleRender() {
        renderWork?.cancel()
        renderEpoch += 1
        let epoch = renderEpoch
        let scale = zoomScale
        let frameSize = block.frame.size
        guard case .pdfPage(let payload) = block.payload,
              let sourceRef = block.pdfSourceRef else { return }
        let pageIndex = payload.pageIndex
        let work = DispatchWorkItem {
            let pixels = PDFTile.pixelSize(
                frame: Size(width: frameSize.width, height: frameSize.height),
                zoomScale: scale,
                displayScale: Double(displayScale)
            )
            guard pixels != .zero,
                  let rendered = PDFVectorRenderer.render(
                      ref: sourceRef, pageIndex: pageIndex,
                      pixels: CGSize(width: pixels.width, height: pixels.height)
                  ) else { return }
            if epoch == renderEpoch {
                image = rendered
            }
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
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
