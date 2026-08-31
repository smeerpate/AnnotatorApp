import CoreGraphics
import Foundation

/// Writes the Edge Impulse "bounding-box-labels" format:
///
///     edgeimpulse/
///       training/
///         bounding_boxes.labels
///         photo1.jpg …
///       testing/
///         bounding_boxes.labels
///         photo2.jpg …
///
/// This mirrors a real `bounding_boxes.labels` file exported by Edge Impulse
/// Studio itself (confirmed working), not the "files" array shown on Edge
/// Impulse's own documentation page — that documented shape produced
/// repeated "Invalid type" upload failures in practice. The proven format is
/// a flat dictionary keyed by file name:
///
///     {
///         "version": 1,
///         "type": "bounding-box-labels",
///         "boundingBoxes": {
///             "photo1.jpg": [
///                 { "label": "good", "x": 105, "y": 201, "width": 91, "height": 90 }
///             ]
///         }
///     }
///
/// There is no per-photo "category" (the training/testing folder already
/// says that), no whole-image "label", and no "metadata" — this format has
/// no field for either, so neither is written.
struct EdgeImpulseExporter {

    /// Fraction of annotated photos assigned to `testing`. The split is
    /// applied through a stable hash of each file name rather than at random,
    /// so re-exporting after labelling more photos does not reshuffle photos
    /// that were already placed in training or testing — only the new photos
    /// get assigned. That matters once a model has been trained on a given
    /// split: shuffling it on every export would quietly invalidate whatever
    /// validation numbers came out of the previous run.
    var testFraction: Double = 0.2

    private let imageWriter = JPEGImageWriter()

    // MARK: - Internal record

    /// Plain data holder, not `Codable`: the JSON below is written by hand so
    /// that field presence and field order are guaranteed byte-for-byte,
    /// rather than relying on however `JSONEncoder` happens to order a keyed
    /// container.
    private struct FileRecord {
        struct Box {
            let label: String
            let x: Int
            let y: Int
            let width: Int
            let height: Int
        }
        let path: String
        let boxes: [Box]
    }

    // MARK: - Export

    @discardableResult
    func write(entries: [ImageEntry], into folder: URL) throws -> String {
        let fm = FileManager.default
        let root = folder.appendingPathComponent("edgeimpulse", isDirectory: true)
        let trainingDir = root.appendingPathComponent("training", isDirectory: true)
        let testingDir = root.appendingPathComponent("testing", isDirectory: true)
        try fm.createDirectory(at: trainingDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: testingDir, withIntermediateDirectories: true)

        var trainingRecords: [FileRecord] = []
        var testingRecords: [FileRecord] = []
        var copiedCount = 0

        for entry in entries where entry.isAnnotated {
            guard let size = ImageLoader.pixelSize(of: entry.url) else { continue }

            let isTesting = stableUnitInterval(for: entry.id) < testFraction
            let targetDir = isTesting ? testingDir : trainingDir
            // Sanitize before it becomes a destination URL, not after, so the
            // copied file on disk and the dictionary key always match exactly.
            let outputName = sanitized(imageWriter.exportedFileName(for: entry.url))

            let destination = targetDir.appendingPathComponent(outputName)
            if !fm.fileExists(atPath: destination.path) {
                try imageWriter.write(source: entry.url, to: destination)
                copiedCount += 1
            }

            // Edge Impulse wants absolute pixel coordinates, top-left origin,
            // same convention as COCO. Clamp so rounding at the image edge
            // can never push a box outside the frame.
            let boxes: [FileRecord.Box] = entry.boxes.map { box in
                let x = Int((box.rect.minX * size.width).rounded())
                let y = Int((box.rect.minY * size.height).rounded())
                let w = Int((box.rect.width * size.width).rounded())
                let h = Int((box.rect.height * size.height).rounded())
                return FileRecord.Box(
                    label: sanitized(box.label),
                    x: min(max(0, x), Int(size.width) - 1),
                    y: min(max(0, y), Int(size.height) - 1),
                    width: max(1, w),
                    height: max(1, h)
                )
            }

            let record = FileRecord(path: outputName, boxes: boxes)
            if isTesting { testingRecords.append(record) } else { trainingRecords.append(record) }
        }

        try writeLabelsFile(trainingRecords, to: trainingDir)
        try writeLabelsFile(testingRecords, to: testingDir)

        return "\(trainingRecords.count) training, \(testingRecords.count) testing "
             + "(\(copiedCount) photos written) into edgeimpulse/"
    }

    // MARK: - Hand-written JSON

    private func writeLabelsFile(_ records: [FileRecord], to folder: URL) throws {
        var lines: [String] = []
        lines.append("{")
        lines.append("    \"version\": 1,")
        lines.append("    \"type\": \"bounding-box-labels\",")
        lines.append("    \"boundingBoxes\": {")

        for (index, record) in records.enumerated() {
            let isLast = index == records.count - 1
            lines.append("        \(quoted(record.path)): [")
            for (boxIndex, box) in record.boxes.enumerated() {
                let isLastBox = boxIndex == record.boxes.count - 1
                lines.append("            {")
                lines.append("                \"label\": \(quoted(box.label)),")
                lines.append("                \"x\": \(box.x),")
                lines.append("                \"y\": \(box.y),")
                lines.append("                \"width\": \(box.width),")
                lines.append("                \"height\": \(box.height)")
                lines.append("            }" + (isLastBox ? "" : ","))
            }
            lines.append("        ]" + (isLast ? "" : ","))
        }

        lines.append("    }")
        lines.append("}")
        lines.append("") // trailing newline

        let text = lines.joined(separator: "\n")
        try text.write(to: folder.appendingPathComponent("bounding_boxes.labels"),
                       atomically: true, encoding: .utf8)
    }

    /// Quotes and escapes a string for embedding in hand-written JSON.
    /// Delegating to `JSONEncoder` for a single `String` value reuses
    /// Foundation's own escaping (quotes, backslashes, control characters,
    /// unicode) instead of reimplementing it by hand.
    private func quoted(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return "\"\(value)\""
        }
        return text
    }

    /// Collapses any whitespace in a string value down to a single
    /// underscore. Applied to every box label and the photo's file name —
    /// neither is meant to contain spaces, and a stray one (a box label with
    /// a trailing space from autocorrect, a photo picked up with a space in
    /// its name) is exactly the kind of thing a strict ingestion parser can
    /// reject outright rather than trim for you.
    private func sanitized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    }

    /// FNV-1a over the file name's UTF-8 bytes, mapped to 0...1.
    ///
    /// Deliberately not Swift's `String.hashValue`: that hash is seeded
    /// randomly per process launch to resist hash-flooding attacks, so the
    /// same file name would land in a different bucket on every app launch.
    /// FNV-1a has no such seed, so the same photo always lands in the same
    /// split, in this run and in every run after it.
    private func stableUnitInterval(for name: String) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Double(hash % 100_000) / 100_000
    }
}
