import NotabilityCore
import SwiftUI

/// A text block that edits inline when selected and auto-sizes its height to
/// its content (the user's "makes itself automatically bigger/smaller").
struct TextBlockView: View {
    @Bindable var session: CanvasSessionState
    let block: CanvasBlock
    let isSelected: Bool

    @State private var editing = false
    @FocusState private var focused: Bool

    private var text: String { block.textPayload?.text ?? "" }
    private var fontSize: Double { block.textPayload?.fontSize ?? TextBlockLayout.defaultFontSize }

    var body: some View {
        Group {
            if editing {
                TextField("", text: textBinding, axis: .vertical)
                    .font(.system(size: fontSize))
            } else {
                Text(text.isEmpty ? " " : text)
                    .font(.system(size: fontSize))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color(hex: block.textPayload?.colorHex ?? "#1A1A1A"))
        .padding(.horizontal, TextBlockLayout.horizontalPadding)
        .padding(.vertical, TextBlockLayout.verticalPadding)
        .frame(width: max(block.frame.size.width, 1), alignment: .leading)
        .onAppear {
            if isSelected {
                editing = true
                DispatchQueue.main.async { focused = true }
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected {
                editing = true
                DispatchQueue.main.async { focused = true }
            }
        }
        .focused($focused)
        .onChange(of: focused) { _, isFocused in
            if !isFocused && editing {
                editing = false
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
}
