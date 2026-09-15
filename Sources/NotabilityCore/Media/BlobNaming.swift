import Foundation

/// File layout for record blobs inside the app's Documents directory.
///
/// `fileRef` values are relative paths from Documents (e.g. `Media/IMG/x.jpg`)
/// so backups and Phase 11 WebDAV can mirror a stable tree. Full URLs are
/// resolved by the app's BlobStore, not stored.
public enum BlobNaming {
    public static let mediaRoot = "Media"
    public static let imagesDir = "Media/IMG"
    public static let pdfsDir = "Media/PDF"
    public static let audioDir = "Media/AUD"

    public static func imageFileName(ext: String = "jpg") -> String {
        "\(UUID().uuidString).\(ext)"
    }

    public static func pdfFileName() -> String {
        "\(UUID().uuidString).pdf"
    }

    public static func audioFileName() -> String {
        "\(UUID().uuidString).wav"
    }

    public static func imageRef(ext: String = "jpg") -> String {
        "\(imagesDir)/\(imageFileName(ext: ext))"
    }

    public static func pdfRef() -> String {
        "\(pdfsDir)/\(pdfFileName())"
    }

    public static func audioRef() -> String {
        "\(audioDir)/\(audioFileName())"
    }

    /// Thumbnail reference for a PDF source (rasterized page 0). Derives from
    /// the PDF ref: `Media/PDF/<uuid>-thumb.png`.
    public static func pdfThumbRef(for pdfRef: String) -> String {
        let url = URL(fileURLWithPath: pdfRef)
        let base = url.deletingPathExtension().lastPathComponent
        return "\(pdfsDir)/\(base)-thumb.png"
    }

    public static func isMediaRef(_ ref: String) -> Bool {
        ref.hasPrefix(mediaRoot + "/")
    }
}
