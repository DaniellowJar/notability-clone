import NotabilityCore
import SwiftUI

/// Vector page-background pattern, drawn in canvas coordinates so it stays
/// crisp at any zoom. Sized by the parent to the content rect.
struct PageTextureView: View {
    let texture: PageTexture
    let contentWidth: Double
    let contentHeight: Double

    var body: some View {
        ZStack {
            Color(.systemBackground)
            Canvas { context, _ in
                guard texture != .plain else { return }
                let (columns, rows) = texture.columnsAndRows(for: Size(width: contentWidth, height: contentHeight))
                let t = texture.tile
                let ink: GraphicsContext.Shading = .color(.secondary.opacity(0.35))
                var path = Path()
                switch texture {
                case .plain:
                    return
                case .dots:
                    for c in 0..<columns {
                        for r in 0..<rows {
                            path.addEllipse(in: CGRect(x: Double(c) * t + t / 2 - 1.5, y: Double(r) * t + t / 2 - 1.5, width: 3, height: 3))
                        }
                    }
                    context.fill(path, with: ink)
                case .dashedGrid:
                    for c in 0...columns {
                        path.move(to: CGPoint(x: Double(c) * t, y: 0))
                        path.addLine(to: CGPoint(x: Double(c) * t, y: contentHeight))
                    }
                    for r in 0...rows {
                        path.move(to: CGPoint(x: 0, y: Double(r) * t))
                        path.addLine(to: CGPoint(x: contentWidth, y: Double(r) * t))
                    }
                    context.stroke(path, with: ink, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                case .squares:
                    let s = t * 0.5
                    for c in 0..<columns {
                        for r in 0..<rows {
                            path.addRect(CGRect(x: Double(c) * t + (t - s) / 2, y: Double(r) * t + (t - s) / 2, width: s, height: s))
                        }
                    }
                    context.stroke(path, with: ink, lineWidth: 1)
                case .hexagons:
                    for c in 0..<columns {
                        for r in 0..<rows {
                            path.addPath(hexagon(cx: Double(c) * t + t / 2, cy: Double(r) * t + t / 2, radius: t / 2 - 2))
                        }
                    }
                    context.stroke(path, with: ink, lineWidth: 1)
                case .ruledLines:
                    for r in 0...rows {
                        path.move(to: CGPoint(x: 0, y: Double(r) * t))
                        path.addLine(to: CGPoint(x: contentWidth, y: Double(r) * t))
                    }
                    context.stroke(path, with: ink, lineWidth: 1)
                }
            }
        }
        .frame(width: CGFloat(contentWidth), height: CGFloat(contentHeight))
    }

    private func hexagon(cx: Double, cy: Double, radius: Double) -> Path {
        var p = Path()
        for i in 0..<6 {
            let a = Double(i) * .pi / 3
            let pt = CGPoint(x: cx + radius * cos(a), y: cy + radius * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
