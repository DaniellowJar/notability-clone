import NotabilityCore
import PDFKit
import UIKit

/// Rasterizes PDF page 0 into a PNG thumbnail stored at `ref` (attachment-mode
/// card art). Returns the ref on success, nil on failure.
enum PDFThumbnailRenderer {
    @discardableResult
    static func render(url: URL, to ref: String, maxDimension: CGFloat = 480) -> String? {
        guard let document = PDFDocument(url: url), let page = document.page(at: 0) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale = min(maxDimension / pageRect.width, maxDimension / pageRect.height)
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else { return nil }
        guard let png = UIImage(cgImage: cgImage).pngData() else { return nil }
        do {
            try BlobStore.shared.save(png, as: ref)
            return ref
        } catch {
            return nil
        }
    }
}
