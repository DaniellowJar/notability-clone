import NotabilityCore
import SwiftUI
import UIKit

/// Viewport-filling host for pinch-zoom and two-finger pan. The recognizers
/// attach to the *window* (found via didMoveToWindow) rather than this view:
/// a topmost overlay would swallow single-finger touches meant for ink,
/// marquee, and blocks, while recognizers on a common ancestor observe every
/// touch without intercepting any. Single-finger touches are never claimed
/// (both recognizers require two touches + `cancelsTouchesInView = false`), so
/// all existing single-finger behavior below is untouched.
struct ZoomPanOverlay: UIViewRepresentable {
    let session: CanvasSessionState

    func makeUIView(context: Context) -> ZoomPanHostView {
        let view = ZoomPanHostView()
        view.onPinchBegan = { [weak session = session] in session?.pinchBegan() }
        view.onPinchChanged = { [weak session = session] relativeScale, anchor in
            session?.pinchChanged(
                relativeScale: relativeScale,
                anchorScreen: Point(x: anchor.x, y: anchor.y)
            )
        }
        view.onPinchEnded = { [weak session = session] in session?.pinchEnded() }
        view.onPan = { [weak session = session] dx, dy in session?.panBy(Point(x: dx, y: dy)) }
        return view
    }

    func updateUIView(_ uiView: ZoomPanHostView, context: Context) {}
}

final class ZoomPanHostView: UIView {
    var onPinchBegan: (() -> Void)?
    var onPinchChanged: ((Double, CGPoint) -> Void)?
    var onPinchEnded: (() -> Void)?
    var onPan: ((Double, Double) -> Void)?

    private var pinch: UIPinchGestureRecognizer?
    private var pan: UIPanGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        // Never intercept hit-testing itself; the window-level recognizers
        // below observe touches while everything underneath keeps working.
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = self
        window.addGestureRecognizer(pinch)
        self.pinch = pinch
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = self
        window.addGestureRecognizer(pan)
        self.pan = pan
    }

    private func detach() {
        if let pinch, let window = pinch.view {
            window.removeGestureRecognizer(pinch)
        }
        if let pan, let window = pan.view {
            window.removeGestureRecognizer(pan)
        }
        pinch = nil
        pan = nil
    }

    /// Only handle gestures fully inside the canvas viewport with no modal
    /// sheet up (a sheet means the user's attention is elsewhere).
    private func shouldHandle(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture.numberOfTouches == 2, let window = self.window else { return false }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        if top != window.rootViewController { return false }
        for i in 0..<2 {
            let p = gesture.location(ofTouch: i, in: self)
            guard bounds.contains(p) else { return false }
        }
        return true
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard shouldHandle(gesture) else { gesture.isEnabled = false; gesture.isEnabled = true; return }
            onPinchBegan?()
        case .changed:
            guard shouldHandle(gesture) else { return }
            onPinchChanged?(Double(gesture.scale), gesture.location(in: self))
        case .ended, .cancelled, .failed:
            onPinchEnded?()
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, shouldHandle(gesture) else { return }
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)
        onPan?(Double(translation.x), Double(translation.y))
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
