import Foundation

/// Persisted app preferences. These are ordinary UI preferences (UserDefaults
/// is fine); API keys are Keychain-only per the build prompt §9.
///
/// "Don't cycle": once `allowFingerDrawing` is turned on (a Settings toggle
/// coming later), a Pencil scribble never disables finger painting again —
/// the preference stays on and is respected on every canvas open.
final class AppSettings {
    static let shared = AppSettings()

    private static let allowFingerDrawingKey = "allowFingerDrawing"
    private static let touchLockedByPencilKey = "touchLockedByPencil"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// User explicitly enabled finger painting. Defaults to off.
    var allowFingerDrawing: Bool {
        get { defaults.bool(forKey: Self.allowFingerDrawingKey) }
        set { defaults.set(newValue, forKey: Self.allowFingerDrawingKey) }
    }

    /// Set automatically the first time a Pencil scribbles while finger
    /// painting is not explicitly enabled. Persists across launches so touch
    /// stays off for pencil users instead of silently re-enabling.
    var touchLockedByPencil: Bool {
        get { defaults.bool(forKey: Self.touchLockedByPencilKey) }
        set { defaults.set(newValue, forKey: Self.touchLockedByPencilKey) }
    }

    /// Clears both preferences — used by UI tests (isolated, -inMemoryStore runs)
    /// so a previous run can't leave the canvas touch-locked.
    func resetForTesting() {
        defaults.removeObject(forKey: Self.allowFingerDrawingKey)
        defaults.removeObject(forKey: Self.touchLockedByPencilKey)
    }
}

/// Pure decision logic for the canvas input policy, kept testable without
/// PencilKit. "Allow touch" == `PKCanvasView.drawingPolicy` `.anyInput` vs
/// `.pencilOnly`.
enum CanvasInputPolicy {
    /// Policy for a freshly opened canvas: touch is allowed until a Pencil
    /// scribbles and locks it (unless the user explicitly enabled fingers).
    static func touchAllowedOnOpen(allowFingerDrawing: Bool, touchLockedByPencil: Bool) -> Bool {
        allowFingerDrawing || !touchLockedByPencil
    }

    /// Outcome of a first Pencil scribble: touch gets locked off unless finger
    /// painting was explicitly enabled — and then it stays on (never cycles).
    static func shouldLockTouch(afterPencilUse allowFingerDrawing: Bool) -> Bool {
        !allowFingerDrawing
    }
}
