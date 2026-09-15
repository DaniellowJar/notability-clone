import NotabilityCore
import PDFKit
import UIKit

/// Phase 10: PDF extract mode — rasterize a chosen page at high resolution
/// into an ImageBlock the user can inspect/draw on.
enum PDFExtractService {
    /// Rasterizes `pageIndex` of the PDF at `pdfURL` at high DPI, stores it as
    /// `Media/PDF/<base>-p<i>.jpg`, and returns the ref.
    @discardableResult
    static func extractPage(pdfURL: URL, pageIndex: Int = 0, scaleFactor: CGFloat = 3) -> String? {
        guard let document = PDFDocument(url: pdfURL), let page = document.page(at: pageIndex) else { return nil }
        let pageRect = page.bounds(for: .mediaBox)
        let size = CGSize(width: pageRect.width * scaleFactor, height: pageRect.height * scaleFactor)
        guard size.width > 0, size.height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage(),
              let jpg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9) else { return nil }
        let base = URL(fileURLWithPath: pdfURL.lastPathComponent).deletingPathExtension().lastPathComponent
        let ref = "\(BlobNaming.pdfsDir)/\(base)-p\(pageIndex).jpg"
        do {
            try BlobStore.shared.save(jpg, as: ref)
            return ref
        } catch {
            return nil
        }
    }
}
