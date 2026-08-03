import CoreGraphics
import ImageIO
import Foundation

/// CGImage is not Sendable, so it travels wrapped.
struct LoadedImage: @unchecked Sendable {
    let cgImage: CGImage
    var size: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
}

/// Decodes a screen-sized version of each photo instead of the full frame.
/// A 20 megapixel source decodes in a fraction of the time this way, which is
/// what keeps Next feeling instant.
actor ImageLoader {

    private let cache = NSCache<NSURL, CGImage>()

    init() {
        cache.countLimit = 16
    }

    func load(_ url: URL, maxPixel: Int = 2400) -> LoadedImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return LoadedImage(cgImage: cached)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // applies EXIF rotation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        cache.setObject(image, forKey: url as NSURL)
        return LoadedImage(cgImage: image)
    }

    /// Warms the cache so the next photo is already decoded when you tap Next.
    func prefetch(_ urls: [URL]) {
        for url in urls where cache.object(forKey: url as NSURL) == nil {
            _ = load(url)
        }
    }

    /// True pixel dimensions of the original, rotation applied. Needed for COCO
    /// export only, so it is read lazily and never decodes the image.
    nonisolated static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated = (5...8).contains(orientation)
        return rotated
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}
