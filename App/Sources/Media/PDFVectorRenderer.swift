import NotabilityCore
import PDFKit
import UIKit

/// Resolution-independent PDF page rendering. Instead of baking one fixed
/// raster (which pixelates on zoom), blocks render the vector page live at
/// exactly the pixels the current zoom needs. Results are cached per
/// (ref, page, pixel size); small card thumbnails stay pre-baked rasters.
enum PDFVectorRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    /// Renders `pageIndex` of the PDF at `ref` to exactly `pixels` (point size
    /// already multiplied out by the caller), aspect-fit with white bars.
    static func render(ref: String, pageIndex: Int, pixels: CGSize) -> UIImage? {
        let key = "\(ref):\(pageIndex):\(Int(pixels.width))x\(Int(pixels.height))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = BlobStore.shared.url(for: ref)
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else { return nil }
        let w = Int(pixels.width), h = Int(pixels.height)
        guard w > 0, h > 0 else { return nil }
        let mediaBox = page.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // Map media box onto the pixel rect, aspect-fit and centered.
        // Transforms apply left-to-right: shift origin, scale (Y-flipped),
        // then shift into place — so the minimum corner lands bottom-left.
        let s = min(CGFloat(w) / mediaBox.width, CGFloat(h) / mediaBox.height)
        let dw = mediaBox.width * s, dh = mediaBox.height * s
        let ox = (CGFloat(w) - dw) / 2, oy = (CGFloat(h) - dh) / 2
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        context.scaleBy(x: s, y: -s)
        context.translateBy(x: ox, y: oy + dh)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    static func clearCache() {
        cache.removeAllObjects()
    }
}
