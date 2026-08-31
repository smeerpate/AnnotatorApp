import SwiftUI

/// Full label management: rename any existing label (updating every box that
/// uses it), delete one, or add a new one. Opened from the pencil button in
/// the label bar so the person is never stuck with whatever names they
/// started with.
struct LabelManagerView: View {
    @Environment(AnnotationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var newLabelText = ""
    @State private var editingLabel: String?
    @State private var draftText = ""
    @State private var pendingDeletion: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.labels, id: \.self) { label in
                        row(for: label)
                    }
                } footer: {
                    Text("Renaming updates every box that uses this label. At least one label has to remain.")
                }

                Section {
                    HStack {
                        TextField("New label name", text: $newLabelText)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .onSubmit(addNewLabel)
                        Button("Add", action: addNewLabel)
                            .disabled(newLabelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Labels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                deletionMessage,
                isPresented: Binding(get: { pendingDeletion != nil },
                                     set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete label", role: .destructive) {
                    if let label = pendingDeletion { store.deleteLabel(label) }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
        }
    }

    @ViewBuilder
    private func row(for label: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color(for: label))
                .frame(width: 12, height: 12)

            if editingLabel == label {
                TextField("Label name", text: $draftText)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit { commitRename(from: label) }

                Button {
                    commitRename(from: label)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)

                Button {
                    editingLabel = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else {
                Text(label)
                Spacer()
                Text("\(store.boxCount(for: label))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard editingLabel != label else { return }
            editingLabel = label
            draftText = label
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = label
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(store.labels.count <= 1)
        }
    }

    // MARK: - Actions

    private func addNewLabel() {
        store.addLabel(newLabelText)
        newLabelText = ""
    }

    private func commitRename(from original: String) {
        store.renameLabel(original, to: draftText)
        editingLabel = nil
    }

    private var deletionMessage: String {
        guard let label = pendingDeletion else { return "" }
        let count = store.boxCount(for: label)
        guard count > 0 else { return "Delete “\(label)”?" }
        return "\(count) box\(count == 1 ? "" : "es") use “\(label)”. Deleting the label deletes those boxes too."
    }

    private func color(for label: String) -> Color {
        let rgb = LabelPalette.colors[LabelPalette.index(for: label, in: store.labels)]
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
