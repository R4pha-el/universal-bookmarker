import SwiftUI

@main
struct UniversalBookmarkerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: LibraryStore?
    @State private var launchError: String?

    init() {
        do {
            let testing = ProcessInfo.processInfo.arguments.contains("--uitesting-demo")
            let created = try LibraryStore(inMemory: testing, configuration: testing ? nil : .load())
            if testing { try created.loadDemoLibrary() }
            _store = State(initialValue: created)
            _launchError = State(initialValue: nil)
        } catch {
            _store = State(initialValue: nil)
            _launchError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    RootView(store: store)
                        .task { await store.start() }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active { Task { await store.start() } }
                        }
                } else {
                    ContentUnavailableView {
                        Label("Your library could not open", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(launchError ?? "Your saved data has been kept. Close the app and try again.")
                    }
                }
            }
        }
    }
}
