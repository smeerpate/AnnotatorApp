import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConversionError: LocalizedError {
    case cannotDecode(String)
    case cannotEncode(String)

    var errorDescription: String? {
        switch self {
        case .cannotDecode(let name): return "Could not decode \(name)."
        case .cannotEncode(let name): return "Could not write \(name) as JPEG."
        }
    }
}

/// Guarantees every exported photo is a JPEG, since that is the one format
/// every training framework and vision platform reads without a conversion
/// step of its own.
///
/// Photos already JPEG are copied byte-for-byte. Anything else (PNG, HEIC,
/// TIFF, BMP, WEBP, …) is decoded and re-encoded, with two details that avoid
/// noisy ImageIO console warnings:
///   - the thumbnail is requested at the source's own pixel size, never more,
///     since asking for more than exists triggers a size warning
///   - the decode always comes back with an alpha channel even for an opaque
///     source, so it gets flattened onto an opaque canvas before JPEG
///     encoding, which has no alpha channel to give it in the first place
struct JPEGImageWriter {

    private static let passthroughExtensions: Set<String> = ["jpg", "jpeg"]

    /// The file name the photo will have once exported, with the extension
    /// swapped to `.jpg` for anything that is not already JPEG.
    func exportedFileName(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if Self.passthroughExtensions.contains(ext) { return url.lastPathComponent }
        return "\(url.deletingPathExtension().lastPathComponent).jpg"
    }

    func write(source url: URL, to destination: URL) throws {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if Self.passthroughExtensions.contains(ext) {
            try FileManager.default.copyItem(at: url, to: destination)
            return
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageConversionError.cannotDecode(name)
        }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = props[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        else {
            throw ImageConversionError.cannotDecode(name)
        }
        let maxDimension = max(pixelWidth, pixelHeight)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageConversionError.cannotDecode(name)
        }

        let image = flattened(decoded)

        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ImageConversionError.cannotEncode(name)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ImageConversionError.cannotEncode(name)
        }
    }

    private func flattened(_ image: CGImage) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return image
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }
}
