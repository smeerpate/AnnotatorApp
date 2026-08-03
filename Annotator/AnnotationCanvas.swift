import SwiftUI

/// Maps between view points and the normalised 0...1 image space.
struct FitLayout {
    let imageSize: CGSize
    let container: CGSize

    var frame: CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2,
                      y: (container.height - h) / 2,
                      width: w, height: h)
    }

    func viewRect(_ normalised: CGRect) -> CGRect {
        let f = frame
        return CGRect(x: f.minX + normalised.minX * f.width,
                      y: f.minY + normalised.minY * f.height,
                      width: normalised.width * f.width,
                      height: normalised.height * f.height)
    }

    func normalisedRect(_ view: CGRect) -> CGRect {
        let f = frame
        guard f.width > 0, f.height > 0 else { return .zero }
        return CGRect(x: (view.minX - f.minX) / f.width,
                      y: (view.minY - f.minY) / f.height,
                      width: view.width / f.width,
                      height: view.height / f.height)
            .clampedToUnitSquare()
    }
}

extension CGRect {
    func clampedToUnitSquare() -> CGRect {
        let minX = Swift.max(0, Swift.min(1, self.minX))
        let minY = Swift.max(0, Swift.min(1, self.minY))
        let maxX = Swift.max(0, Swift.min(1, self.maxX))
        let maxY = Swift.max(0, Swift.min(1, self.maxY))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func between(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
         CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY)]
    }

    /// The corner diagonally opposite the given one.
    func opposite(of corner: CGPoint) -> CGPoint {
        CGPoint(x: corner.x == minX ? maxX : minX,
                y: corner.y == minY ? maxY : minY)
    }
}

private enum DragMode {
    case idle
    case drawing(start: CGPoint)
    case moving(id: UUID, origin: CGRect, start: CGPoint)
    case resizing(id: UUID, anchor: CGPoint)
}

struct AnnotationCanvas: View {
    @Environment(AnnotationStore.self) private var store

    let entry: ImageEntry
    let image: CGImage

    @State private var mode: DragMode = .idle
    @State private var draft: CGRect?

    private let handleTouchRadius: CGFloat = 26
    private let handleDrawRadius: CGFloat = 7
    private let minimumDrawSize: CGFloat = 12

    var body: some View {
        let boxes = entry.boxes
        let selectedID = store.selectedBoxID
        let labels = store.labels

        GeometryReader { geo in
            let layout = FitLayout(imageSize: CGSize(width: image.width, height: image.height),
                                   container: geo.size)
            let frame = layout.frame

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                Canvas { context, _ in
                    for box in boxes {
                        let rect = layout.viewRect(box.rect)
                        let color = color(for: box.label, labels: labels)
                        let isSelected = box.id == selectedID

                        context.stroke(Path(roundedRect: rect, cornerRadius: 4),
                                       with: .color(color),
                                       lineWidth: isSelected ? 3 : 1.8)

                        if isSelected {
                            context.fill(Path(roundedRect: rect, cornerRadius: 4),
                                         with: .color(color.opacity(0.14)))
                            for corner in rect.corners {
                                let dot = CGRect(x: corner.x - handleDrawRadius,
                                                 y: corner.y - handleDrawRadius,
                                                 width: handleDrawRadius * 2,
                                                 height: handleDrawRadius * 2)
                                context.fill(Path(ellipseIn: dot), with: .color(.white))
                                context.stroke(Path(ellipseIn: dot), with: .color(color), lineWidth: 2.5)
                            }
                        }

                        drawChip(box.label, color: color, at: rect, in: &context)
                    }

                    if let draft {
                        context.stroke(Path(roundedRect: draft, cornerRadius: 4),
                                       with: .color(color(for: store.activeLabel, labels: labels)),
                                       style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .allowsHitTesting(false)

                DrawingSurface(
                    pencilOnly: store.pencilOnly,
                    onBegan: { point in began(at: point, layout: layout, boxes: boxes, selectedID: selectedID) },
                    onMoved: { point in moved(to: point, layout: layout) },
                    onEnded: { point in ended(at: point, layout: layout) },
                    onCancelled: { mode = .idle; draft = nil }
                )
            }
        }
    }

    // MARK: - Interaction

    private func began(at point: CGPoint, layout: FitLayout, boxes: [BoxAnnotation], selectedID: UUID?) {
        // A handle of the selected box wins over everything else.
        if let id = selectedID, let box = boxes.first(where: { $0.id == id }) {
            let rect = layout.viewRect(box.rect)
            if let corner = rect.corners.first(where: { distance($0, point) <= handleTouchRadius }) {
                mode = .resizing(id: id, anchor: rect.opposite(of: corner))
                draft = CGRect.between(rect.opposite(of: corner), point)
                return
            }
        }

        // Topmost box under the pen gets picked up and moved.
        if let box = boxes.reversed().first(where: { layout.viewRect($0.rect).contains(point) }) {
            store.selectedBoxID = box.id
            mode = .moving(id: box.id, origin: box.rect, start: point)
            return
        }

        // Empty space: deselect and start a new box.
        store.selectedBoxID = nil
        mode = .drawing(start: point)
        draft = CGRect.between(point, point)
    }

    private func moved(to point: CGPoint, layout: FitLayout) {
        switch mode {
        case .drawing(let start):
            draft = CGRect.between(start, point)

        case .resizing(_, let anchor):
            draft = CGRect.between(anchor, point)

        case .moving(let id, let origin, let start):
            let frame = layout.frame
            guard frame.width > 0, frame.height > 0 else { return }
            let dx = (point.x - start.x) / frame.width
            let dy = (point.y - start.y) / frame.height
            var moved = origin.offsetBy(dx: dx, dy: dy)
            // Keep the whole box on the image instead of clipping it.
            moved.origin.x = min(max(0, moved.minX), 1 - moved.width)
            moved.origin.y = min(max(0, moved.minY), 1 - moved.height)
            store.updateRect(id, to: moved)

        case .idle:
            break
        }
    }

    private func ended(at point: CGPoint, layout: FitLayout) {
        defer { mode = .idle; draft = nil }

        switch mode {
        case .drawing(let start):
            let rect = CGRect.between(start, point)
            guard rect.width >= minimumDrawSize, rect.height >= minimumDrawSize else { return }
            store.addBox(rect: layout.normalisedRect(rect))

        case .resizing(let id, let anchor):
            let rect = CGRect.between(anchor, point)
            guard rect.width >= minimumDrawSize, rect.height >= minimumDrawSize else { return }
            store.updateRect(id, to: layout.normalisedRect(rect))

        case .moving, .idle:
            break
        }
    }

    // MARK: - Drawing helpers

    private func drawChip(_ label: String, color: Color, at rect: CGRect, in context: inout GraphicsContext) {
        let text = Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
        let resolved = context.resolve(text)
        let size = resolved.measure(in: CGSize(width: 200, height: 40))
        let chip = CGRect(x: rect.minX,
                          y: max(0, rect.minY - size.height - 6),
                          width: size.width + 12,
                          height: size.height + 4)
        context.fill(Path(roundedRect: chip, cornerRadius: 4), with: .color(color))
        context.draw(resolved,
                     at: CGPoint(x: chip.midX, y: chip.midY),
                     anchor: .center)
    }

    private func color(for label: String, labels: [String]) -> Color {
        let rgb = LabelPalette.colors[LabelPalette.index(for: label, in: labels)]
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
