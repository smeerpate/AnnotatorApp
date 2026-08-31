import CoreGraphics
import Foundation

/// Turns the in-app annotations into the two formats every training pipeline
/// understands. Written into a `dataset/` subfolder so the photo folder stays clean.
///
/// Image conversion (forcing everything to JPEG) is shared with the other
/// exporters through `JPEGImageWriter`.
struct DatasetExporter {

    private let imageWriter = JPEGImageWriter()

    func write(entries: [ImageEntry], labels: [String], into folder: URL) throws -> String {
        let fm = FileManager.default
        let root = folder.appendingPathComponent("dataset", isDirectory: true)
        let labelsDir = root.appendingPathComponent("labels", isDirectory: true)
        let imagesDir = root.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: labelsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        try labels.joined(separator: "\n")
            .write(to: root.appendingPathComponent("classes.txt"),
                   atomically: true, encoding: .utf8)

        try dataYAML(labels: labels)
            .write(to: root.appendingPathComponent("data.yaml"),
                   atomically: true, encoding: .utf8)

        var coco = COCO()
        coco.categories = labels.enumerated().map {
            COCO.Category(id: $0.offset + 1, name: $0.element, supercategory: "object")
        }

        var imageID = 1
        var annotationID = 1
        var boxCount = 0

        var copiedCount = 0

        for entry in entries where entry.isAnnotated {
            let stem = entry.url.deletingPathExtension().lastPathComponent
            let outputName = imageWriter.exportedFileName(for: entry.url)

            // The photo itself. YOLO expects images/ and labels/ side by side
            // with matching stems, so the copy is not optional.
            let destination = imagesDir.appendingPathComponent(outputName)
            if !fm.fileExists(atPath: destination.path) {
                try imageWriter.write(source: entry.url, to: destination)
                copiedCount += 1
            }

            // YOLO: class cx cy w h, all normalised. No pixel size needed.
            let lines = entry.boxes.compactMap { box -> String? in
                guard let classIndex = labels.firstIndex(of: box.label) else { return nil }
                return String(format: "%d %.6f %.6f %.6f %.6f",
                              classIndex,
                              Double(box.rect.midX), Double(box.rect.midY),
                              Double(box.rect.width), Double(box.rect.height))
            }
            try lines.joined(separator: "\n")
                .write(to: labelsDir.appendingPathComponent("\(stem).txt"),
                       atomically: true, encoding: .utf8)

            // COCO needs real pixels, read from the file header without decoding.
            let size = ImageLoader.pixelSize(of: entry.url) ?? CGSize(width: 1, height: 1)
            coco.images.append(COCO.Image(id: imageID,
                                          fileName: "images/\(outputName)",
                                          width: Int(size.width),
                                          height: Int(size.height)))

            for box in entry.boxes {
                guard let classIndex = labels.firstIndex(of: box.label) else { continue }
                let x = Double(box.rect.minX) * Double(size.width)
                let y = Double(box.rect.minY) * Double(size.height)
                let w = Double(box.rect.width) * Double(size.width)
                let h = Double(box.rect.height) * Double(size.height)

                coco.annotations.append(COCO.Annotation(id: annotationID,
                                                        imageId: imageID,
                                                        categoryId: classIndex + 1,
                                                        bbox: [x, y, w, h],
                                                        area: w * h,
                                                        iscrowd: 0))
                annotationID += 1
                boxCount += 1
            }
            imageID += 1
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(coco).write(to: root.appendingPathComponent("coco.json"))

        return "\(boxCount) boxes and \(copiedCount) photos into dataset/ (\(imageID - 1) images total)"
    }

    /// Minimal Ultralytics-style config. Train and val point at the same folder:
    /// split them properly once you have enough photos to hold some back.
    private func dataYAML(labels: [String]) -> String {
        let names = labels.enumerated()
            .map { "  \($0.offset): \($0.element)" }
            .joined(separator: "\n")
        return """
        path: .
        train: images
        val: images

        names:
        \(names)
        """
    }
}

// MARK: - Minimal COCO detection format

struct COCO: Codable {
    struct Image: Codable {
        let id: Int
        let fileName: String
        let width: Int
        let height: Int

        enum CodingKeys: String, CodingKey {
            case id, width, height
            case fileName = "file_name"
        }
    }

    struct Annotation: Codable {
        let id: Int
        let imageId: Int
        let categoryId: Int
        /// [x, y, width, height] in pixels, origin top-left.
        let bbox: [Double]
        let area: Double
        let iscrowd: Int

        enum CodingKeys: String, CodingKey {
            case id, bbox, area, iscrowd
            case imageId = "image_id"
            case categoryId = "category_id"
        }
    }

    struct Category: Codable {
        let id: Int
        let name: String
        let supercategory: String
    }

    var images: [Image] = []
    var annotations: [Annotation] = []
    var categories: [Category] = []
}
