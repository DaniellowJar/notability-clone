import XCTest
@testable import NotabilityClone

final class CanvasInputPolicyTests: XCTestCase {
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testFreshCanvasAllowsTouch() {
        // No pencil used yet, finger painting not enabled → touch draws.
        XCTAssertTrue(CanvasInputPolicy.touchAllowedOnOpen(allowFingerDrawing: false, touchLockedByPencil: false))
    }

    func testPreviouslyLockedCanvasOpensPencilOnly() {
        // A pencil scribbled in a past session and fingers aren't enabled → touch stays off.
        XCTAssertFalse(CanvasInputPolicy.touchAllowedOnOpen(allowFingerDrawing: false, touchLockedByPencil: true))
    }

    func testFingerDrawingEnabledAlwaysAllowsTouch() {
        // Explicitly enabled fingers must win over any prior pencil lock.
        XCTAssertTrue(CanvasInputPolicy.touchAllowedOnOpen(allowFingerDrawing: true, touchLockedByPencil: true))
    }

    func testPencilScribbleLocksTouchUnlessFingerDrawingEnabled() {
        XCTAssertTrue(CanvasInputPolicy.shouldLockTouch(afterPencilUse: false))
        XCTAssertFalse(CanvasInputPolicy.shouldLockTouch(afterPencilUse: true))
    }

    func testFingerDrawingPreferenceDefaultsOffAndPersists() {
        let settings = makeSettings()
        XCTAssertFalse(settings.allowFingerDrawing)
        XCTAssertFalse(settings.touchLockedByPencil)

        // "If I turn on painting with fingers, it should stay on."
        settings.allowFingerDrawing = true
        XCTAssertTrue(settings.allowFingerDrawing)
        XCTAssertFalse(settings.touchLockedByPencil, "enabling fingers must not mark a pencil lock")
    }

    func testPencilLockPersistsAcrossSessions() {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        let first = AppSettings(defaults: suite)
        first.touchLockedByPencil = true

        // A second instance reading the same store sees the lock — no cycling back.
        let second = AppSettings(defaults: suite)
        XCTAssertTrue(second.touchLockedByPencil)
        XCTAssertFalse(CanvasInputPolicy.touchAllowedOnOpen(allowFingerDrawing: second.allowFingerDrawing,
                                                           touchLockedByPencil: second.touchLockedByPencil))
    }
}
