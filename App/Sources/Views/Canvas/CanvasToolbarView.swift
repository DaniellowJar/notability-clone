import NotabilityCore
import PhotosUI
import SwiftUI
import UIKit

/// Floating top toolbar for the canvas: insert tools (text / photo / camera /
/// PDF / select) in draw mode, a contextual bar (delete + font stepper) while
/// editing a block, and a Done/hint bar during area-select and tap-to-place.
struct CanvasToolbarView: View {
    @Bindable var session: CanvasSessionState

    @State private var photosItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var cameraError: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                switch session.mode {
                case .draw:
                    insertTools
                case .editingBlock(let id):
                    editingBar(blockID: id)
                default:
                    cancelBar
                }
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)

            if let hint = modeHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.top, 8)
        .alert("Camera", isPresented: cameraAlertBinding) {
        } message: {
            Text(cameraError ?? "")
        }
    }

    // MARK: - Insert tools (draw mode)

    private var insertTools: some View {
        HStack(spacing: 2) {
            ToolButton(title: "T", id: "toolText") { session.startTextTool() }
            PhotosPicker(selection: $photosItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("toolPhoto")
            ToolButton(systemImage: "camera", id: "toolCamera") { openCamera() }
            ToolButton(systemImage: "doc", id: "toolPDF") { showImporter = true }
            ToolButton(systemImage: "lasso", id: "toolSelect") { session.startSelectTool() }
            ToolButton(systemImage: "function", id: "toolCalc") { session.startPlaceCalc() }
            ToolButton(systemImage: "textformat.size", id: "toolLetter") { session.toggleLetterMode() }
        }
        .onChange(of: photosItem) { _, item in
            guard let item else { return }
            photosItem = nil
            Task { await handle(photosItem: item) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            handle(pdfImport: result)
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9), let ref = saveImage(data) {
                    session.startPlaceImage(ref: ref)
                }
            }
        }
    }

    // MARK: - Editing a block

    private func editingBar(blockID: UUID) -> some View {
        HStack(spacing: 2) {
            ToolButton(systemImage: "trash", id: "blockDelete", tint: .red) {
                session.deleteBlock(blockID)
            }
            if let block = session.blocks.first(where: { $0.id == blockID }),
               case .text = block.payload {
                Divider().frame(height: 20)
                FontSizeStepper(
                    value: block.textPayload?.fontSize ?? TextBlockLayout.defaultFontSize
                ) { size in
                    session.setTextFontSize(blockID, size: size)
                }
            }
            ToolButton(title: "Done", id: "toolDone") { session.deselect() }
        }
    }

    // MARK: - Area select / tap-to-place

    private var cancelBar: some View {
        HStack(spacing: 2) {
            ToolButton(title: "Done", id: "toolDone") { session.cancelTool() }
        }
    }

    private var modeHint: String? {
        switch session.mode {
        case .draw: nil
        case .areaSelect(.newTextBlock): "Drag to create a text block"
        case .areaSelect(.selectBlocks): "Drag or tap to select a block"
        case .tapToPlace(.image): "Tap the canvas to place the image"
        case .tapToPlace(.pdf): "Tap the canvas to place the PDF"
        case .tapToPlace(.calc): "Tap the canvas to place the calculator"
        case .editingBlock: "Tap a block to select · drag to move · Done to finish"
        }
    }

    // MARK: - Pickers → blobs

    private func handle(photosItem: PhotosPickerItem) async {
        guard let data = try? await photosItem.loadTransferable(type: Data.self) else {
            session.errorMessage = "Could not load the selected photo"
            return
        }
        guard let ref = saveImage(data) else {
            session.errorMessage = "Could not store the photo"
            return
        }
        session.startPlaceImage(ref: ref)
    }

    private func handle(pdfImport result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let pdfRef = BlobNaming.pdfRef()
            let thumbRef = BlobNaming.pdfThumbRef(for: pdfRef)
            do {
                try BlobStore.shared.save(Data(contentsOf: url), as: pdfRef)
                PDFThumbnailRenderer.render(url: BlobStore.shared.url(for: pdfRef), to: thumbRef)
                session.startPlacePDF(ref: pdfRef, thumbRef: thumbRef)
            } catch {
                session.errorMessage = "Could not import the PDF: \(error.localizedDescription)"
            }
        case .failure(let error):
            session.errorMessage = "PDF import failed: \(error.localizedDescription)"
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraError = "Camera is not available on this device."
            return
        }
        showCamera = true
    }

    private func saveImage(_ data: Data) -> String? {
        let ref = BlobNaming.imageRef()
        do {
            try BlobStore.shared.save(data, as: ref)
            return ref
        } catch {
            return nil
        }
    }

    private var cameraAlertBinding: Binding<Bool> {
        Binding(
            get: { cameraError != nil },
            set: { if !$0 { cameraError = nil } }
        )
    }
}

/// A 44×44 touch-target tool button.
private struct ToolButton: View {
    let title: String?
    let systemImage: String?
    let id: String
    var tint: Color = .primary
    let action: () -> Void

    init(title: String? = nil, systemImage: String? = nil, id: String, tint: Color = .primary, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.id = id
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else if let title {
                    Text(title)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }
}
