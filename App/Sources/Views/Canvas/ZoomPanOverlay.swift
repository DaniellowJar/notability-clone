import NotabilityCore
import SwiftUI
import UIKit

/// Viewport-filling host for Maps-style simultaneous zoom+drag. A single
/// custom two-finger recognizer (attached to the window, found via
/// didMoveToWindow) emits incremental scale-about-moving-anchor plus
/// translation on every event. Two separate recognizers fought over the same
/// touches (pinch recomputed from a fixed base while pan also fired, and
/// per-event gating dropped mid-gesture frames) — that was the choppiness.
///
/// A topmost overlay can't be used: it would swallow single-finger touches
/// meant for ink, marquee, and blocks. Recognizers on the common ancestor
/// observe every touch without intercepting any, and both require two touches
/// (`cancelsTouchesInView = false`), so single-finger behavior is untouched.
struct ZoomPanOverlay: UIViewRepresentable {
    let session: CanvasSessionState

    func makeUIView(context: Context) -> ZoomPanHostView {
        let view = ZoomPanHostView()
        view.onZoomPan = { [weak session = session] ratio, translation, anchor in
            session?.applyZoomPan(
                scaleRatio: ratio,
                anchorScreen: Point(x: anchor.x, y: anchor.y),
                pan: Point(x: translation.x, y: translation.y)
            )
        }
        return view
    }

    func updateUIView(_ uiView: ZoomPanHostView, context: Context) {}
}

/// Tracks exactly two touches, reporting incremental span ratio, midpoint
/// translation, and midpoint anchor on every move. Fails cleanly otherwise.
final class PinchPanGestureRecognizer: UIGestureRecognizer {
    /// (scaleRatio, translation, anchor) — all in host-viewport coordinates.
    var onChange: ((Double, CGPoint, CGPoint) -> Void)?

    private weak var host: UIView?
    private var tracked: [UITouch] = []
    private var lastSpan: CGFloat = 0
    private var lastMid: CGPoint = .zero

    init(host: UIView) {
        self.host = host
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
    }

    private func spanAndMid() -> (span: CGFloat, mid: CGPoint)? {
        guard let host, tracked.count == 2 else { return nil }
        let a = tracked[0].location(in: host)
        let b = tracked[1].location(in: host)
        let dx = a.x - b.x, dy = a.y - b.y
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        return (max(hypot(dx, dy), 1), mid)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        tracked.append(contentsOf: touches)
        if tracked.count == 2, let sm = spanAndMid() {
            lastSpan = sm.span
            lastMid = sm.mid
            state = .began
        } else if tracked.count > 2 {
            state = .failed
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard (state == .began || state == .changed), let sm = spanAndMid() else { return }
        let ratio = sm.span / max(lastSpan, 1)
        let dx = sm.mid.x - lastMid.x, dy = sm.mid.y - lastMid.y
        lastSpan = sm.span
        lastMid = sm.mid
        onChange?(Double(ratio), CGPoint(x: dx, y: dy), sm.mid)
        state = .changed
    }

    private func endTracking(_ touches: Set<UITouch>) {
        tracked.removeAll { touches.contains($0) }
        if tracked.count < 2 {
            state = (state == .began || state == .changed) ? .ended : .failed
            tracked = []
        } else if let sm = spanAndMid() {
            lastSpan = sm.span
            lastMid = sm.mid
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        endTracking(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        endTracking(touches)
    }

    override func reset() {
        super.reset()
        tracked = []
    }
}

final class ZoomPanHostView: UIView {
    var onZoomPan: ((Double, CGPoint, CGPoint) -> Void)?

    private var recognizer: PinchPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        // Never intercept hit-testing itself; the window-level recognizer
        // observes touches while everything underneath keeps working.
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard window != nil else { return }
        let recognizer = PinchPanGestureRecognizer(host: self)
        recognizer.delegate = self
        recognizer.onChange = { [weak self] ratio, translation, anchor in
            self?.handleZoomPan(ratio: ratio, translation: translation, anchor: anchor)
        }
        window?.addGestureRecognizer(recognizer)
        self.recognizer = recognizer
    }

    private func detach() {
        if let recognizer, let window = recognizer.view {
            window.removeGestureRecognizer(recognizer)
        }
        recognizer = nil
    }

    /// Only handle gestures fully inside the canvas viewport with no modal
    /// sheet up (a sheet means the user's attention is elsewhere). Checked
    /// once at the start — never mid-gesture, so frames can't drop out.
    private func shouldHandle() -> Bool {
        guard let window = self.window else { return false }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        if top != window.rootViewController { return false }
        return true
    }

    private func handleZoomPan(ratio: Double, translation: CGPoint, anchor: CGPoint) {
        guard shouldHandle() else { return }
        guard bounds.contains(anchor) else { return }
        onZoomPan?(ratio, translation, anchor)
    }
}

extension ZoomPanHostView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
