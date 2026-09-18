import NotabilityCore
import SwiftUI
import UIKit

/// SwiftUI wrapper for the opaque custom-ink view. Never intercepts touches.
struct InkRenderView: UIViewRepresentable {
    let strokes: [StrokeData]
    let style: InkRenderingStyle
    let liveStroke: StrokeData?
    let zoomScale: Double
    /// Bumped when stroke geometry is rewritten out-of-band (e.g. a Letter Mode
    /// commit) without changing the stroke count, forcing a full rebuild.
    let rewriteToken: Int

    func makeUIView(context: Context) -> InkCanvasView {
        InkCanvasView()
    }

    func updateUIView(_ uiView: InkCanvasView, context: Context) {
        uiView.strokes = strokes
        uiView.style = style
        uiView.liveStroke = liveStroke
        uiView.zoomScale = zoomScale
        uiView.rewriteToken = rewriteToken
    }
}

enum InkRenderingStyle: Equatable {
    case normal
    case letterMode
}

/// Opaque view that renders the captured strokes as vector `CAShapeLayer`s.
/// It covers the PKCanvasView (same background) so the canvas's own ink is
/// hidden and the app controls exactly what is drawn — required for Phase 5
/// correction and Phase 6 Letter Mode. Never intercepts touches.
///
/// Each stroke is a real vector path. Core Animation rasterizes vector layers
/// at the final composited resolution, so the parent `.scaleEffect` zoom does
/// not blur them the way a `draw(_:)` backing store baked at 1x would (that is
/// what produced the pixelated strokes). Updating an in-progress stroke is just
/// a path swap, so live ink stays smooth, and there is no giant backing store
/// to blow past the OS layer-size limit at deep zoom.
final class InkCanvasView: UIView {
    var strokes: [StrokeData] = [] {
        didSet { rebuildStrokeLayers() }
    }
    var style: InkRenderingStyle = .normal {
        didSet { rebuildStrokeLayers() }
    }
    /// In-progress stroke preview (touch-tracked). Drawn last at full color so
    /// ink is visible while painting even under the opaque letter layer.
    var liveStroke: StrokeData? {
        didSet { updateLiveLayer() }
    }
    /// Retained for the representable's API; vector layers need no manual
    /// backing-store scale (Core Animation handles zoom resolution).
    var zoomScale: Double = 1
    /// Bumped by the session after out-of-band store edits (Letter Mode commit)
    /// that rewrite points without changing the stroke count.
    var rewriteToken: Int = 0 {
        didSet {
            guard rewriteToken != oldValue else { return }
            renderedStyle = nil
            rebuildStrokeLayers()
        }
    }

    private var strokeLayers: [CAShapeLayer] = []
    private let liveLayer = CAShapeLayer()
    private var renderedCount = -1
    private var renderedStyle: InkRenderingStyle?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        isOpaque = true
        isUserInteractionEnabled = false
        configure(liveLayer)
        layer.addSublayer(liveLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ shape: CAShapeLayer) {
        shape.fillColor = nil
        shape.lineCap = .round
        shape.lineJoin = .round
    }

    /// The strokes to draw, with the color/alpha each should use. Normal mode
    /// draws everything at full opacity; Letter Mode hides all but the trailing
    /// ~3 clusters, fading them toward grey.
    private func displaySpecs() -> [(stroke: StrokeData, colorHex: String, alpha: Double)] {
        switch style {
        case .normal:
            return strokes.map { ($0, $0.colorHex, 1) }
        case .letterMode:
            let clusters = LetterMode.letterClusters(strokes: strokes)
            var specs: [(StrokeData, String, Double)] = []
            for (ci, cluster) in clusters.enumerated() {
                let alpha = LetterMode.clusterAlpha(positionsBackFromNewest: clusters.count - 1 - ci)
                guard alpha > 0 else { continue }
                for stroke in cluster {
                    let hex = LetterModeAging.fadedColor(inkHex: stroke.colorHex, ageFraction: 1 - alpha)
                    specs.append((stroke, hex, alpha))
                }
            }
            return specs
        }
    }

    private func rebuildStrokeLayers() {
        // Normal mode is the drawing hot path: avoid building a full specs
        // array on every touch event — only the last stroke changes mid-stroke.
        if style == .normal {
            let styleChanged = renderedStyle != .normal
            if styleChanged || strokes.count != renderedCount {
                syncPool(to: strokes.count)
                for (i, stroke) in strokes.enumerated() {
                    apply((stroke, stroke.colorHex, 1), to: strokeLayers[i])
                }
            } else if let stroke = strokes.last, let lastLayer = strokeLayers.last {
                apply((stroke, stroke.colorHex, 1), to: lastLayer)
            }
            renderedCount = strokes.count
            renderedStyle = .normal
            return
        }

        let specs = displaySpecs()
        let styleChanged = renderedStyle != style
        let countChanged = specs.count != renderedCount
        if styleChanged || countChanged {
            syncPool(to: specs.count)
            for (i, spec) in specs.enumerated() {
                apply(spec, to: strokeLayers[i])
            }
        } else if let spec = specs.last, let lastLayer = strokeLayers.last {
            apply(spec, to: lastLayer)
        }
        renderedCount = specs.count
        renderedStyle = style
    }

    private func syncPool(to count: Int) {
        while strokeLayers.count < count {
            let shape = CAShapeLayer()
            configure(shape)
            // Keep every stroke below the live preview layer.
            layer.insertSublayer(shape, below: liveLayer)
            strokeLayers.append(shape)
        }
        if strokeLayers.count > count {
            for shape in strokeLayers[count...] { shape.removeFromSuperlayer() }
            strokeLayers.removeLast(strokeLayers.count - count)
        }
    }

    private func apply(
        _ spec: (stroke: StrokeData, colorHex: String, alpha: Double),
        to shape: CAShapeLayer
    ) {
        shape.path = Self.path(for: spec.stroke)
        shape.strokeColor = UIColor(hex: spec.colorHex)
            .withAlphaComponent(CGFloat(spec.alpha)).cgColor
        shape.lineWidth = CGFloat(spec.stroke.baseWidth)
    }

    private func updateLiveLayer() {
        guard let live = liveStroke, let path = Self.path(for: live) else {
            liveLayer.isHidden = true
            liveLayer.path = nil
            return
        }
        liveLayer.isHidden = false
        liveLayer.path = path
        liveLayer.strokeColor = UIColor(hex: live.colorHex).cgColor
        liveLayer.lineWidth = CGFloat(live.baseWidth)
    }

    /// Vector path from corrected points when present, else raw capture points.
    private static func path(for stroke: StrokeData) -> CGPath? {
        let points = stroke.correctedPoints ?? stroke.points
        guard let first = points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: first.location.x, y: first.location.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.location.x, y: point.location.y))
        }
        return path
    }
}
