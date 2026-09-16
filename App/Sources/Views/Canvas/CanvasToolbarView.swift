import NotabilityCore
import SwiftUI
import UIKit

/// Floating top toolbar for the canvas: insert tools (text / photo / camera /
/// PDF / select) in draw mode, a contextual bar (delete + font stepper) while
/// editing a block, and a Done/hint bar during area-select and tap-to-place.
struct CanvasToolbarView: View {
    @Bindable var session: CanvasSessionState

    var isRecording = false
    var onToggleRecord: () -> Void = {}
    var onShowTranscript: () -> Void = {}
    var onShowQuiz: () -> Void = {}
    var onExtractPDF: (UUID) -> Void = { _ in }
    var onRemoveBackground: (UUID) -> Void = { _ in }

    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showImporter = false
    @State private var cameraError: String?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if session.letterArea != nil {
                    letterBar
                } else {
                    switch session.mode {
                    case .draw:
                        insertTools
                    case .editingBlock(let id):
                        editingBar(blockID: id)
                    default:
                        cancelBar
                    }
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
            ToolButton(systemImage: "photo", id: "toolPhoto") { showPhotoLibrary = true }
            ToolButton(systemImage: "camera", id: "toolCamera") { openCamera() }
            ToolButton(systemImage: "doc", id: "toolPDF") { showImporter = true }
            ToolButton(systemImage: "lasso", id: "toolSelect") { session.startSelectTool() }
            ToolButton(systemImage: "function", id: "toolCalc") { session.startPlaceCalc() }
            ToolButton(systemImage: "textformat.size", id: "toolLetter") { session.startLetterArea() }
            Divider().frame(height: 20)
            ToolButton(systemImage: isRecording ? "stop.circle.fill" : "mic", id: "toolRecord", tint: isRecording ? .red : .primary) { onToggleRecord() }
            ToolButton(systemImage: "waveform", id: "toolTranscript") { onShowTranscript() }
            ToolButton(systemImage: "list.number", id: "toolQuiz") { onShowQuiz() }
        }
        .sheet(isPresented: $showPhotoLibrary) {
            PhotoLibraryPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9), let ref = saveImage(data) {
                    session.startPlaceImage(ref: ref)
                } else {
                    session.errorMessage = "Could not store the photo"
                }
            }
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
            if let block = session.blocks.first(where: { $0.id == blockID }) {
                contextContent(for: block, blockID: blockID)
            }
            ToolButton(title: "Done", id: "toolDone") { session.deselect() }
        }
    }

    @ViewBuilder
    private func contextContent(for block: CanvasBlock, blockID: UUID) -> some View {
        switch block.payload {
        case .text:
            Divider().frame(height: 20)
            FontSizeStepper(
                value: block.textPayload?.fontSize ?? TextBlockLayout.defaultFontSize
            ) { size in
                session.setTextFontSize(blockID, size: size)
            }
        case .pdfPage:
            Divider().frame(height: 20)
            ToolButton(systemImage: "doc.richtext", id: "extractPDF") {
                onExtractPDF(blockID)
            }
        case .image:
            Divider().frame(height: 20)
            ToolButton(systemImage: "wand.and.stars", id: "removeBackground") {
                onRemoveBackground(blockID)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Area select / tap-to-place

    private var cancelBar: some View {
        HStack(spacing: 2) {
            ToolButton(title: "Done", id: "toolDone") { session.cancelTool() }
        }
    }

    private var letterBar: some View {
        HStack(spacing: 2) {
            ToolButton(title: "Done", id: "toolDone") { session.exitLetterMode() }
        }
    }

    private var modeHint: String? {
        if session.letterArea != nil { return "Write big — the camera follows · Done to finish" }
        switch session.mode {
        case .draw: return nil
        case .areaSelect(.newTextBlock): return "Drag to create a text block"
        case .areaSelect(.selectBlocks): return "Drag or tap to select a block"
        case .areaSelect(.letterArea): return "Drag to select the letter area"
        case .tapToPlace(.image): return "Tap the canvas to place the image"
        case .tapToPlace(.pdf): return "Tap the canvas to place the PDF"
        case .tapToPlace(.calc): return "Tap the canvas to place the calculator"
        case .editingBlock: return "Tap a block to select · drag to move · Done to finish"
        }
    }

    // MARK: - Pickers → blobs

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
