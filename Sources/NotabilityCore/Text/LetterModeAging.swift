import Foundation

/// Letter Mode (Phase 6): age strokes by how long ago / how far left of the
/// current writing position they were drawn, fading newest ink in the user's
/// color through mid-gray to light gray — old text stays faintly visible.
public enum LetterModeAging {
    /// 0 = newest stroke, 1 = oldest. Uses stroke order; total == count.
    public static func ageFraction(strokeIndex: Int, total: Int) -> Double {
        guard total > 1 else { return 0 }
        return Double(total - 1 - min(max(strokeIndex, 0), total - 1)) / Double(total - 1)
    }

    /// Opacity for a stroke at a given age: newest ≈ 1, oldest ≈ 0.15.
    public static func alpha(ageFraction: Double) -> Double {
        1 - 0.85 * min(max(ageFraction, 0), 1)
    }

    /// Ink color faded toward light gray with age (oldest ≈ light gray).
    public static func fadedColor(inkHex: String, ageFraction: Double) -> String {
        guard let ink = HexColor.parse(inkHex) else { return inkHex }
        let faded = RGBColor.lerp(ink, .lightGray, t: 0.9 * min(max(ageFraction, 0), 1))
        return HexColor.string(faded)
    }

    /// Faded color + alpha combined for a stroke.
    public static func style(inkHex: String, ageFraction: Double) -> (hex: String, alpha: Double) {
        (fadedColor(inkHex: inkHex, ageFraction: ageFraction), alpha(ageFraction: ageFraction))
    }
}
