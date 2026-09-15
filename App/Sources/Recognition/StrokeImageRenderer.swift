import NotabilityCore
import UIKit

/// Renders stroke ink to a UIImage (white background) for Vision recognition.
enum StrokeImageRenderer {
    static func render(strokes: [StrokeData], scale: CGFloat = 2, padding: CGFloat = 24) -> UIImage? {
        let collection = StrokeCollection(strokes: strokes)
        let bounds = collection.bounds
        guard bounds.size.width > 0, bounds.size.height > 0 else { return nil }
        let size = CGSize(
            width: bounds.size.width + padding * 2,
            height: bounds.size.height + padding * 2
        )
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: padding - bounds.minX, y: padding - bounds.minY)
            CoreGraphicsStrokeRenderer().draw(strokes, in: ctx.cgContext)
        }
    }
}
