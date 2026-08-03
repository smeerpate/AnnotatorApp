import SwiftUI

@main
struct NutAnnotatorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AnnotationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { store.restoreLastFolder() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Annotating on the couch means the app gets backgrounded a lot.
            if phase != .active { store.saveNow() }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 900)
        #endif
    }
}
