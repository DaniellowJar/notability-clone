import NotabilityCore
import SwiftUI
import UIKit

/// A text block that edits inline when selected and auto-sizes its height to
/// its content (the user's "makes itself automatically bigger/smaller").
///
/// While zoomed, SwiftUI would rasterize the text at 1x and let the parent
/// `.scaleEffect` magnify the bitmap (blurry). To keep glyphs vector-sharp the
/// non-editing display is rendered with `ImageRenderer` at the on-screen
/// resolution (`zoom × displayScale`), the same resolution-independent pattern
/// used by `InkCanvasView` and the PDF blocks. Editing still uses a live
/// `TextField`; committed text re-rasterizes crisply.
struct TextBlockView: View {
    @Bindable var session: CanvasSessionState
    let block: CanvasBlock
    let isSelected: Bool
    let zoomScale: Double

    @Environment(\.displayScale) private var displayScale
    @State private var editing = false
    @State private var raster: UIImage?
    @State private var rasterEpoch = 0
    @FocusState private var focused: Bool

    private var text: String { block.textPayload?.text ?? "" }
    private var fontSize: Double { block.textPayload?.fontSize ?? TextBlockLayout.defaultFontSize }
    private var color: Color { Color(hex: block.textPayload?.colorHex ?? "#1A1A1A") }

    var body: some View {
        Group {
            if editing {
                TextField("", text: textBinding, axis: .vertical)
                    .font(.system(size: fontSize))
            } else if let raster {
                Image(uiImage: raster)
            } else {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: fontSize))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, TextBlockLayout.horizontalPadding)
        .padding(.vertical, TextBlockLayout.verticalPadding)
        .frame(width: max(block.frame.size.width, 1), alignment: .leading)
        .onAppear {
            scheduleRaster()
            if isSelected {
                editing = true
                DispatchQueue.main.async { focused = true }
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                editing = true
                DispatchQueue.main.async { focused = true }
            } else {
                scheduleRaster()
            }
        }
        .onChange(of: zoomScale) { _, _ in scheduleRaster() }
        .onChange(of: text) { _, _ in scheduleRaster() }
        .onChange(of: fontSize) { _, _ in scheduleRaster() }
        .focused($focused)
        .onChange(of: focused) { _, isFocused in
            if !isFocused && editing {
                editing = false
                scheduleRaster()
                session.flushPendingSaves()
            }
        }
        .readSize { size in
            session.setTextBlockHeight(block.id, height: size.height)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { session.setText(block.id, text: $0) }
        )
    }

    /// Render the display text into a `UIImage` at the current zoom resolution.
    /// Epoch-guarded and slightly debounced so a fast pinch only applies the
    /// latest render.
    private func scheduleRaster() {
        rasterEpoch += 1
        let epoch = rasterEpoch
        let content = renderContent
        let scale = CGFloat(max(zoomScale, 1) * Double(displayScale))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard epoch == rasterEpoch else { return }
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            raster = renderer.uiImage
        }
    }

    /// The text laid out at its wrapped width. Rendered standalone so the
    /// bitmap carries the glyphs at `zoom × displayScale` pixels per point.
    private var renderContent: some View {
        Text(text.isEmpty ? " " : text)
            .font(.system(size: fontSize))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(color)
            .frame(
                width: max(block.frame.size.width - TextBlockLayout.horizontalPadding * 2, 1),
                alignment: .leading
            )
    }
}
