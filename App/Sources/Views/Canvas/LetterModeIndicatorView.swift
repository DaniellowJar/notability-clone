import NotabilityCore
import SwiftUI

/// Phase 6 Letter Mode edge indicator: a thin gauge showing how close the
/// current writing position (the newest stroke) is to the right edge of the
/// canvas. Green = plenty of room, orange = closing in, red = at the edge.
struct LetterModeIndicatorView: View {
    let strokes: [StrokeData]
    let canvasWidth: CGFloat

    private var writingX: CGFloat? {
        guard let newest = strokes.last, let last = newest.points.last else { return nil }
        return CGFloat(last.location.x)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.caption)
                Text("Letter mode")
                    .font(.caption.weight(.medium))
                Spacer()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule().fill(tint).frame(width: 6)
                        .position(x: cursorX(in: proxy.size.width), y: proxy.size.height / 2)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .frame(width: 140)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(12)
    }

    private func cursorX(in width: CGFloat) -> CGFloat {
        guard let writingX, canvasWidth > 0 else { return 0 }
        return min(max(writingX / canvasWidth * width, 3), width - 3)
    }

    private var tint: Color {
        guard let writingX, canvasWidth > 0 else { return .green }
        let distanceToEdge = 1 - writingX / canvasWidth
        if distanceToEdge < 0.2 { return .red }
        if distanceToEdge < 0.4 { return .orange }
        return .green
    }
}
