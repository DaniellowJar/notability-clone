import NotabilityCore
import SwiftUI
import UIKit

/// SwiftUI wrapper for the opaque custom-ink view. Never intercepts touches.
struct InkRenderView: UIViewRepresentable {
    let strokes: [StrokeData]
    let style: InkRenderingStyle
    let liveStroke: StrokeData?
    let zoomScale: Double

    func makeUIView(context: Context) -> InkCanvasView {
        InkCanvasView()
    }

    func updateUIView(_ uiView: InkCanvasView, context: Context) {
        uiView.strokes = strokes
        uiView.style = style
        uiView.liveStroke = liveStroke
        uiView.zoomScale = zoomScale
    }
}

enum InkRenderingStyle: Equatable {
    case normal
    case letterMode
}

/// Opaque view that renders the captured strokes via the custom renderer.
/// It covers the PKCanvasView (same background) so the canvas's own ink is
/// hidden and the app controls exactly what is drawn — required for Phase 5
/// correction and Phase 6 Letter Mode. Never intercepts touches.
final class InkCanvasView: UIView {
    var strokes: [StrokeData] = [] {
        didSet { setNeedsDisplay() }
    }
    var style: InkRenderingStyle = .normal {
        didSet { setNeedsDisplay() }
    }
    /// In-progress stroke preview (touch-tracked). Drawn last at full color so
    /// ink is visible while painting even under the opaque letter layer.
    var liveStroke: StrokeData? {
        didSet { setNeedsDisplay() }
    }
    /// Current canvas zoom. The backing store rescales with it so zoomed ink
    /// re-rasterizes from vectors instead of magnifying a 1x bitmap.
    var zoomScale: Double = 1 {
        didSet {
            updateRasterScale()
            setNeedsDisplay()
        }
    }

    private let renderer = CoreGraphicsStrokeRenderer()
    private let letterRenderer = LetterModeStrokeRenderer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
        updateRasterScale()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateRasterScale()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateRasterScale()
    }

    private func updateRasterScale() {
        let screenScale = window?.screen.scale ?? UIScreen.main.scale
        contentScaleFactor = CanvasTransform.rasterScale(screenScale: Double(screenScale), zoom: zoomScale)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(bounds)
        switch style {
        case .normal:
            renderer.draw(strokes, in: context)
        case .letterMode:
            letterRenderer.draw(strokes, in: context)
        }
        if let live = liveStroke {
            renderer.draw(stroke: live, colorHex: live.colorHex, alpha: 1, in: context)
        }
        context.restoreGState()
    }
}
