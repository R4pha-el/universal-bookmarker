import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct RootView: View {
    @Bindable var store: LibraryStore
    @State private var tab = RootTab.library
    @State private var sheet: RootSheet?
    @State private var nextSource: AddSource?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingFileResult: Result<[URL], Error>?
    @State private var importing = false
    @State private var importError: String?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LibraryView(store: store, onAdd: { sheet = .add })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Account and sync", systemImage: "person.crop.circle") { sheet = .account }
                                .accessibilityIdentifier("toolbar.account")
                                .disabled(importing)
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Add to library", systemImage: "plus") { sheet = .add }
                                .accessibilityIdentifier("toolbar.add")
                                .disabled(importing)
                        }
                    }
            }
            .id(store.scopeID)
            .tabItem { Label("Library", systemImage: "bookmark") }
            .tag(RootTab.library).accessibilityIdentifier("tab.library")
            NavigationStack { CollectionsView(store: store) }
                .id(store.scopeID)
                .tabItem { Label("Collections", systemImage: "folder") }
                .tag(RootTab.collections).accessibilityIdentifier("tab.collections")
            NavigationStack { SearchView(store: store) }
                .id(store.scopeID)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(RootTab.search).accessibilityIdentifier("tab.search")
        }
        .tint(.primary)
        .sheet(item: $sheet, onDismiss: presentNextSource) { destination in
            switch destination {
            case .add:
                AddToLibraryView { source in nextSource = source; sheet = nil }
            case .link: AddLinkView(store: store)
            case .account:
                AccountView(store: store)
                    .task { do { try await store.refreshCaptureCount() } catch { store.errorMessage = error.localizedDescription } }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $selectedPhotos, maxSelectionCount: 20, matching: .images)
        .onChange(of: selectedPhotos) { _, _ in startPhotoImportIfReady() }
        .onChange(of: showPhotos) { _, _ in startPhotoImportIfReady() }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item], allowsMultipleSelection: true, onCompletion: handleFiles)
        .onChange(of: showFiles) { _, _ in startFileImportIfReady() }
        .overlay(alignment: .top) {
            if importing {
                ProgressView("Importing originals…")
                    .padding().background(.regularMaterial, in: .capsule)
                    .padding().accessibilityAddTraits(.updatesFrequently)
            }
        }
        .alert("Library needs attention", isPresented: Binding(get: { importError != nil || store.errorMessage != nil }, set: { if !$0 { importError = nil; store.errorMessage = nil } })) {} message: {
            Text(importError ?? store.errorMessage ?? "Please try again.")
        }
    }

    private func presentNextSource() {
        guard let nextSource else { return }
        self.nextSource = nil
        switch nextSource {
        case .link: sheet = .link
        case .photos: showPhotos = true
        case .files: showFiles = true
        }
    }

    private func handleFiles(_ result: Result<[URL], Error>) {
        pendingFileResult = result
        startFileImportIfReady()
    }

    private func startFileImportIfReady() {
        guard !showFiles, let result = pendingFileResult else { return }
        pendingFileResult = nil
        switch result {
        case .success(let urls):
            Task {
                importing = true
                defer { importing = false }
                do { try await store.importFiles(urls) }
                catch { importError = error.localizedDescription }
            }
        case .failure(let error): importError = error.localizedDescription
        }
    }

    private func startPhotoImportIfReady() {
        guard !showPhotos, !selectedPhotos.isEmpty, !importing else { return }
        let photos = selectedPhotos
        selectedPhotos = []
        Task { await importPhotos(photos) }
    }

    private func importPhotos(_ photos: [PhotosPickerItem]) async {
        importing = true
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            importing = false
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var urls: [URL] = []
            var failures: [String] = []
            for (index, photo) in photos.prefix(20).enumerated() {
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else {
                        throw CocoaError(.fileReadUnknown)
                    }
                    guard data.count <= 25 * 1_024 * 1_024 else {
                        failures.append("Photo \(index + 1) is larger than 25 MB.")
                        continue
                    }
                    let fileExtension = photo.supportedContentTypes.first(where: { $0.conforms(to: .image) })?.preferredFilenameExtension ?? "jpg"
                    let url = directory.appending(path: "Photo \(index + 1).\(fileExtension)")
                    try data.write(to: url, options: .atomic)
                    urls.append(url)
                } catch { failures.append("Photo \(index + 1): \(error.localizedDescription)") }
            }
            if !urls.isEmpty {
                do { try await store.importFiles(urls) }
                catch { failures.append(error.localizedDescription) }
            }
            if !failures.isEmpty { importError = failures.joined(separator: "\n") }
        } catch { importError = error.localizedDescription }
    }
}
