import UIKit

extension UIColor {
    convenience init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r, g, b, a: CGFloat
        switch value.count {
        case 8:
            r = CGFloat((int >> 24) & 0xFF) / 255
            g = CGFloat((int >> 16) & 0xFF) / 255
            b = CGFloat((int >> 8) & 0xFF) / 255
            a = CGFloat(int & 0xFF) / 255
        default:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >> 8) & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
            a = 1
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    /// "#RRGGBB" (alpha dropped). Resolves dynamic colors (e.g. `.label`)
    /// against the current trait collection — `getRed` returns `false` for
    /// dynamic colors and left the hex as garbage, making default ink
    /// invisible or wrong-colored on-device.
    var hexString: String {
        hexString(resolvedWith: UITraitCollection.current)
    }

    /// Same as `hexString`, but resolved against an explicit trait collection.
    /// Prefer this with the canvas's own traits (`canvas.traitCollection`)
    /// from touch/delegate callbacks: the ambient
    /// `UITraitCollection.current` is unreliable during touch dispatch and
    /// misresolved white picker ink as black in Letter Mode.
    func hexString(resolvedWith traits: UITraitCollection) -> String {
        let resolved = resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
        if let components = resolved.cgColor
            .converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
           components.count >= 3 {
            return String(format: "#%02X%02X%02X", Int(components[0] * 255), Int(components[1] * 255), Int(components[2] * 255))
        }
        return "#000000"
    }
}
