import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class AnnotationStore {

    // MARK: - State

    private(set) var folderURL: URL?
    private(set) var entries: [ImageEntry] = []
    var index = 0

    var labels: [String] = ["good", "defect"]
    var activeLabel = "good"
    var selectedBoxID: UUID?

    var pencilOnly = true
    var status = "Choose the folder with your photos."

    let loader = ImageLoader()

    private var scopedURL: URL?
    private var saveTask: Task<Void, Never>?
    private static let bookmarkKey = "annotationFolderBookmark"

    private static let imageExtensions: Set<String> =
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp"]

    // MARK: - Derived

    var current: ImageEntry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    var annotatedCount: Int {
        entries.filter(\.isAnnotated).count
    }

    var totalBoxes: Int {
        entries.reduce(0) { $0 + $1.boxes.count }
    }

    var canGoNext: Bool { index < entries.count - 1 }
    var canGoBack: Bool { index > 0 }

    var selectedBox: BoxAnnotation? {
        guard let id = selectedBoxID else { return nil }
        return current?.boxes.first { $0.id == id }
    }

    // MARK: - Folder

    func restoreLastFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        #if os(macOS)
        let url = try? URL(resolvingBookmarkData: data,
                           options: [.withSecurityScope],
                           relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        #else
        let url = try? URL(resolvingBookmarkData: data,
                           relativeTo: nil,
                           bookmarkDataIsStale: &stale)
        #endif
        if let url { open(folder: url) }
    }

    func open(folder: URL) {
        releaseFolder()

        guard folder.startAccessingSecurityScopedResource() else {
            status = "No permission to read that folder."
            return
        }
        scopedURL = folder
        folderURL = folder
        storeBookmark(for: folder)

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
            entries = files
                .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map(ImageEntry.init(url:))
        } catch {
            entries = []
            status = "Could not read the folder: \(error.localizedDescription)"
            return
        }

        index = 0
        selectedBoxID = nil
        loadAnnotations()

        // Resume where the work stopped rather than at photo one.
        if let firstUnlabelled = entries.firstIndex(where: { !$0.isAnnotated }) {
            index = firstUnlabelled
        }

        status = entries.isEmpty
            ? "No images found in \(folder.lastPathComponent)."
            : "\(entries.count) images in \(folder.lastPathComponent)."
        prefetchNeighbours()
    }

    func releaseFolder() {
        saveNow()
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func storeBookmark(for folder: URL) {
        #if os(macOS)
        let data = try? folder.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
        #else
        let data = try? folder.bookmarkData(options: [],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
        #endif
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    // MARK: - Navigation

    func goNext() {
        guard canGoNext else { return }
        index += 1
        selectedBoxID = nil
        prefetchNeighbours()
    }

    func goBack() {
        guard canGoBack else { return }
        index -= 1
        selectedBoxID = nil
        prefetchNeighbours()
    }

    /// Jumps to the next photo that has no boxes yet.
    func goToNextUnlabelled() {
        guard !entries.isEmpty else { return }
        let ahead = entries.indices.contains(index + 1)
            ? entries[(index + 1)...].firstIndex(where: { !$0.isAnnotated })
            : nil
        guard let target = ahead ?? entries.firstIndex(where: { !$0.isAnnotated }) else {
            status = "Every photo has at least one box."
            return
        }
        index = target
        selectedBoxID = nil
        prefetchNeighbours()
    }

    private func prefetchNeighbours() {
        let urls = [index - 1, index + 1, index + 2]
            .filter { entries.indices.contains($0) }
            .map { entries[$0].url }
        guard !urls.isEmpty else { return }
        Task { await loader.prefetch(urls) }
    }

    // MARK: - Editing

    @discardableResult
    func addBox(rect: CGRect) -> UUID? {
        guard let entry = current else { return nil }
        let box = BoxAnnotation(label: activeLabel, rect: rect.standardized)
        guard box.isUsable else { return nil }
        entry.boxes.append(box)
        selectedBoxID = box.id
        scheduleSave()
        return box.id
    }

    func updateRect(_ id: UUID, to rect: CGRect) {
        guard let entry = current,
              let position = entry.boxes.firstIndex(where: { $0.id == id }) else { return }
        entry.boxes[position].rect = rect.standardized
        scheduleSave()
    }

    func deleteSelected() {
        guard let entry = current, let id = selectedBoxID else { return }
        entry.boxes.removeAll { $0.id == id }
        selectedBoxID = nil
        scheduleSave()
    }

    func clearCurrent() {
        guard let entry = current else { return }
        entry.boxes.removeAll()
        selectedBoxID = nil
        scheduleSave()
    }

    /// Tapping a label relabels the selected box, or arms it for the next draw.
    func applyLabel(_ label: String) {
        activeLabel = label
        guard let entry = current, let id = selectedBoxID,
              let position = entry.boxes.firstIndex(where: { $0.id == id }) else { return }
        entry.boxes[position].label = label
        scheduleSave()
    }

    func addLabel(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !labels.contains(name) else { return }
        labels.append(name)
        activeLabel = name
        scheduleSave()
    }

    /// Renames a label everywhere it is used. If the new name collides with an
    /// existing label, the two are merged instead of ending up with a
    /// duplicate — every box under the old name simply becomes the existing one.
    func renameLabel(_ old: String, to raw: String) {
        let new = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old, let index = labels.firstIndex(of: old) else { return }

        if labels.contains(new) {
            labels.remove(at: index)
        } else {
            labels[index] = new
        }
        for entry in entries {
            for i in entry.boxes.indices where entry.boxes[i].label == old {
                entry.boxes[i].label = new
            }
        }
        if activeLabel == old { activeLabel = new }
        scheduleSave()
    }

    /// Removes a label and every box that used it. Refuses to remove the last
    /// remaining label, since every new box needs something to be labelled.
    func deleteLabel(_ label: String) {
        guard labels.count > 1, let index = labels.firstIndex(of: label) else { return }
        labels.remove(at: index)
        for entry in entries {
            entry.boxes.removeAll { $0.label == label }
        }
        if activeLabel == label { activeLabel = labels.first ?? "" }
        scheduleSave()
    }

    /// How many boxes, across every photo, currently use this label. Shown
    /// before a delete so the person knows what they are about to lose.
    func boxCount(for label: String) -> Int {
        entries.reduce(0) { $0 + $1.boxes.filter { $0.label == label }.count }
    }

    // MARK: - Persistence

    private var annotationsURL: URL? {
        folderURL?.appendingPathComponent("annotations.json")
    }

    private func loadAnnotations() {
        guard let url = annotationsURL,
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(AnnotationFile.self, from: data)
        else { return }

        if !file.labels.isEmpty {
            labels = file.labels
            activeLabel = file.labels.first ?? activeLabel
        }
        for entry in entries {
            entry.boxes = file.images[entry.id] ?? []
        }
    }

    /// Debounced so dragging a box does not hammer the disk.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard let url = annotationsURL else { return }
        var images: [String: [BoxAnnotation]] = [:]
        for entry in entries where entry.isAnnotated {
            images[entry.id] = entry.boxes
        }
        let file = AnnotationFile(labels: labels, images: images)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(file).write(to: url, options: .atomic)
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: - Export

    func exportDatasetFiles() {
        guard let folder = folderURL else { return }
        saveNow()
        do {
            let summary = try DatasetExporter().write(entries: entries, labels: labels, into: folder)
            status = "Wrote \(summary) next to your photos."
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportEdgeImpulse() {
        guard let folder = folderURL else { return }
        saveNow()
        do {
            let summary = try EdgeImpulseExporter().write(entries: entries, into: folder)
            status = "Wrote \(summary)"
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }
}
