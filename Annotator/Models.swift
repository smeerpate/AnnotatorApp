import CoreGraphics
import Foundation
import Observation

/// One bounding box. `rect` is normalised to 0...1 with the origin top-left,
/// so it stays valid whatever resolution the image is shown at.
struct BoxAnnotation: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var rect: CGRect

    /// Guards against zero-size boxes from a stray tap.
    var isUsable: Bool { rect.width > 0.002 && rect.height > 0.002 }
}

@Observable
final class ImageEntry: Identifiable {
    let id: String          // file name, used as the key on disk
    let url: URL
    var boxes: [BoxAnnotation] = []

    var isAnnotated: Bool { !boxes.isEmpty }

    init(url: URL) {
        self.url = url
        self.id = url.lastPathComponent
    }
}

/// What gets written to `annotations.json` in the image folder.
struct AnnotationFile: Codable {
    var version = 1
    var labels: [String]
    /// file name -> boxes
    var images: [String: [BoxAnnotation]]
}

/// Stable colour per label so the same class always looks the same.
enum LabelPalette {
    static let colors: [(r: Double, g: Double, b: Double)] = [
        (0.20, 0.85, 0.45),   // green
        (1.00, 0.45, 0.20),   // orange
        (0.30, 0.70, 1.00),   // blue
        (1.00, 0.35, 0.60),   // pink
        (0.95, 0.85, 0.25),   // yellow
        (0.65, 0.45, 1.00)    // violet
    ]

    static func index(for label: String, in labels: [String]) -> Int {
        (labels.firstIndex(of: label) ?? 0) % colors.count
    }
}
