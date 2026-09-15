import Foundation

/// Simple sRGB color (0…1 components) for cross-platform math (Letter Mode
/// aging, blending). Not tied to UIKit/CoreGraphics.
public struct RGBColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = RGBColor(red: 0, green: 0, blue: 0)
    public static let lightGray = RGBColor(red: 0.82, green: 0.82, blue: 0.82)

    public static func lerp(_ a: RGBColor, _ b: RGBColor, t: Double) -> RGBColor {
        let t = min(max(t, 0), 1)
        return RGBColor(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t,
            alpha: a.alpha + (b.alpha - a.alpha) * t
        )
    }
}

public enum HexColor {
    /// Parses "#RRGGBB" / "#RRGGBBAA" (leading `#` optional). nil on garbage.
    public static func parse(_ hex: String) -> RGBColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard let int = UInt64(value, radix: 16) else { return nil }
        switch value.count {
        case 6:
            return RGBColor(
                red: Double((int >> 16) & 0xFF) / 255,
                green: Double((int >> 8) & 0xFF) / 255,
                blue: Double(int & 0xFF) / 255
            )
        case 8:
            return RGBColor(
                red: Double((int >> 24) & 0xFF) / 255,
                green: Double((int >> 16) & 0xFF) / 255,
                blue: Double((int >> 8) & 0xFF) / 255,
                alpha: Double(int & 0xFF) / 255
            )
        default:
            return nil
        }
    }

    public static func string(_ color: RGBColor) -> String {
        String(format: "#%02X%02X%02X",
               Int((color.red * 255).rounded()),
               Int((color.green * 255).rounded()),
               Int((color.blue * 255).rounded()))
    }
}
