import Foundation

/// Pure sizing estimates for text blocks. The SwiftUI text view reconciles
/// these estimates with real UIKit measurement and persists the result via
/// `updateBlockFrame`, so the estimates only need to be deterministic and
/// close — tests assert the math, not exact typography.
public enum TextBlockLayout {
    public static let horizontalPadding: Double = 12
    public static let verticalPadding: Double = 8
    public static let defaultFontSize: Double = 17
    public static let minFontSize: Double = 10
    public static let maxFontSize: Double = 72
    /// Common body sizes offered by the font stepper's preset menu.
    public static let presetFontSizes: [Double] = [11, 13, 15, 17, 20, 24, 28, 34, 40]

    /// Height of one line of text at a given font size.
    public static func lineHeight(fontSize: Double) -> Double { fontSize * 1.4 }

    /// Average advance width of a character at a given font size.
    public static func charWidth(fontSize: Double) -> Double { fontSize * 0.5 }

    /// Clamps a font size to the allowed range.
    public static func clampedFontSize(_ size: Double) -> Double {
        min(max(size, minFontSize), maxFontSize)
    }

    /// Deterministic line estimate: wraps by average character width and adds
    /// explicit newlines. Overestimates slightly; the view shrinks on measure.
    public static func lineCount(
        text: String,
        frameWidth: Double,
        fontSize: Double,
        horizontalPadding: Double = TextBlockLayout.horizontalPadding
    ) -> Int {
        guard !text.isEmpty else { return 1 }
        let usableWidth = max(frameWidth - horizontalPadding * 2, 1)
        let charsPerLine = max(Int(usableWidth / charWidth(fontSize: fontSize)), 1)
        let wrapped = max(1, Int(ceil(Double(text.count) / Double(charsPerLine))))
        let explicitNewlines = text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
        return max(wrapped, explicitNewlines + 1)
    }

    /// Frame for a new text block: width from the marquee (with a floor so a
    /// narrow selection still types comfortably), height grown to fit `text`.
    public static func autoFrame(
        marquee: Rect,
        fontSize: Double,
        text: String,
        horizontalPadding: Double = TextBlockLayout.horizontalPadding,
        verticalPadding: Double = TextBlockLayout.verticalPadding
    ) -> Rect {
        var frame = marquee
        if frame.size.width < 60 { frame.size.width = 60 }
        let lines = lineCount(
            text: text,
            frameWidth: frame.size.width,
            fontSize: fontSize,
            horizontalPadding: horizontalPadding
        )
        frame.size.height = max(
            frame.size.height,
            lineHeight(fontSize: fontSize) * Double(lines) + verticalPadding * 2
        )
        return frame
    }
}
