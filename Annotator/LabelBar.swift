import SwiftUI

/// Tapping a label does one of two things, depending on what is selected:
/// with a box selected it relabels that box, otherwise it arms the label for
/// the next box you draw. One control, no mode switch to remember.
struct LabelBar: View {
    @Environment(AnnotationStore.self) private var store

    let addLabelTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.labels, id: \.self) { label in
                        Button {
                            store.applyLabel(label)
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(color(for: label))
                                    .frame(width: 11, height: 11)
                                Text(label)
                                    .font(.callout.weight(.medium))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(isActive(label)
                                               ? color(for: label).opacity(0.22)
                                               : Color.secondary.opacity(0.12))
                            )
                            .overlay(
                                Capsule().strokeBorder(isActive(label)
                                                       ? color(for: label)
                                                       : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: addLabelTapped) {
                        Label("New label", systemImage: "plus")
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.4),
                                                               style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var hint: String {
        store.selectedBox == nil
            ? "Label for the next box you draw"
            : "Tap a label to apply it to the selected box"
    }

    private func isActive(_ label: String) -> Bool {
        if let selected = store.selectedBox { return selected.label == label }
        return store.activeLabel == label
    }

    private func color(for label: String) -> Color {
        let rgb = LabelPalette.colors[LabelPalette.index(for: label, in: store.labels)]
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
