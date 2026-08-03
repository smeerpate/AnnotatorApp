import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AnnotationStore.self) private var store

    @State private var showingFolderPicker = false
    @State private var showingNewLabel = false
    @State private var newLabelText = ""
    @State private var loaded: LoadedImage?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                canvasArea
                Divider()
                LabelBar(addLabelTapped: { showingNewLabel = true })
                Divider()
                navigationBar
            }
            .navigationTitle(store.current?.id ?? "NutAnnotator")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .task(id: store.current?.url) { await loadCurrent() }
        .onDisappear { store.releaseFolder() }
        .fileImporter(isPresented: $showingFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result { store.open(folder: folder) }
        }
        .alert("New label", isPresented: $showingNewLabel) {
            TextField("Name", text: $newLabelText)
            Button("Add") {
                store.addLabel(newLabelText)
                newLabelText = ""
            }
            Button("Cancel", role: .cancel) { newLabelText = "" }
        } message: {
            Text("Labels are shared across every photo in this folder.")
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvasArea: some View {
        ZStack {
            Color.black.opacity(0.92)

            if store.folderURL == nil {
                emptyState
            } else if let entry = store.current, let loaded {
                AnnotationCanvas(entry: entry, image: loaded.cgImage)
                    .id(entry.id)
            } else if isLoading {
                ProgressView().tint(.white)
            } else {
                Text("No images in this folder.")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44, weight: .light))
            Text("Pick the folder with your photos")
                .font(.title3.weight(.medium))
            Text("Every image in it gets shown one at a time. Draw a box with the Pencil, tap a label, then move on.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .foregroundStyle(.secondary)
            Button("Choose folder") { showingFolderPicker = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(40)
    }

    // MARK: - Navigation

    private var navigationBar: some View {
        HStack(spacing: 14) {
            Button {
                store.goBack()
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!store.canGoBack)
            .keyboardShortcut(.leftArrow, modifiers: [])

            VStack(spacing: 1) {
                Text(counterText)
                    .font(.callout.monospacedDigit().weight(.medium))
                Text(store.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 200)

            Button {
                store.goNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canGoNext)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var counterText: String {
        guard !store.entries.isEmpty else { return "no photos" }
        return "\(store.index + 1) / \(store.entries.count)  ·  \(store.annotatedCount) done"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Delete box", systemImage: "trash") {
                store.deleteSelected()
            }
            .disabled(store.selectedBoxID == nil)
            .keyboardShortcut(.delete, modifiers: [])
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Toggle("Apple Pencil only", isOn: Bindable(store).pencilOnly)
                Divider()
                Button("Next photo without boxes", systemImage: "forward.end") {
                    store.goToNextUnlabelled()
                }
                Button("Clear boxes on this photo", systemImage: "eraser", role: .destructive) {
                    store.clearCurrent()
                }
                Divider()
                Button("Export YOLO and COCO", systemImage: "square.and.arrow.up") {
                    store.exportDatasetFiles()
                }
                Button("Choose another folder", systemImage: "folder") {
                    showingFolderPicker = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Loading

    private func loadCurrent() async {
        guard let entry = store.current else {
            loaded = nil
            return
        }
        isLoading = true
        let result = await store.loader.load(entry.url)
        // The user may have tapped Next while this was decoding.
        guard store.current?.url == entry.url else { return }
        loaded = result
        isLoading = false
        if result == nil {
            store.status = "Could not read \(entry.id)."
        }
    }
}
