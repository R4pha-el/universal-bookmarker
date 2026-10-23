import SwiftUI
import BookmarkCore
import QuickLook

struct ItemDetailView: View {
    let store: LibraryStore
    @State var item: BookmarkItem
    @State private var errorMessage: String?
    @State private var showDelete = false
    @State private var showSafari = false
    @State private var previewURL: URL?
    @State private var showOriginal = false
    @State private var downloading = false
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                if item.kind == .photo, let url = store.fileURL(for: item) {
                    ItemArtwork(item: item, fileURL: url).frame(height: 220)
                }
                Label(LibraryDesign.source(item), systemImage: LibraryDesign.symbol(item.kind))
                    .foregroundStyle(.secondary)
                if item.kind == .link, let url = item.url {
                    Button("Preview website", systemImage: "safari") { showSafari = true }
                    Button("Open in browser", systemImage: "arrow.up.right.square") { openURL(url) }
                } else {
                    Button(action: previewOriginal) {
                        if downloading { ProgressView("Downloading original…") }
                        else { Label("Preview original", systemImage: "doc.text.magnifyingglass") }
                    }.disabled(downloading)
                }
            }
            Section("Title") {
                TextField("Title", text: $item.title, axis: .vertical).lineLimit(1...4)
                    .accessibilityIdentifier("detail.title")
            }
            Section("Note") {
                TextField("Add a note", text: $item.note, axis: .vertical).lineLimit(3...8)
            }
            Section("Organisation") {
                Picker("Collection", selection: $item.collectionID) {
                    Text("No collection").tag(nil as UUID?)
                    ForEach(store.collections.filter { $0.deletedAt == nil }) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
            }
            Section {
                LabeledContent("Saved", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let byteCount = item.byteCount {
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                }
                if let filename = item.filename { LabeledContent("Original filename", value: filename) }
                if let shareURL = item.url ?? previewURL ?? store.fileURL(for: item) {
                    ShareLink(item: shareURL) { Label("Share original", systemImage: "square.and.arrow.up") }
                }
                Button("Delete item", systemImage: "trash", role: .destructive) { showDelete = true }
            }
            if saved { Text("Changes saved").foregroundStyle(.secondary).accessibilityIdentifier("detail.saved") }
        }
        .navigationTitle("Saved item")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, _ in saved = false }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save changes", action: save)
                    .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showSafari) {
            if let url = item.url { SafariPreview(url: url).ignoresSafeArea() }
        }
        .sheet(isPresented: $showOriginal) {
            if let previewURL { OriginalPreview(url: previewURL).ignoresSafeArea() }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete item", role: .destructive, action: delete)
        } message: { Text("This removes the saved item and its original from your library.") }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {} message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func save() {
        do { try store.updateItem(item); saved = true }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete() {
        do { try store.deleteItem(item); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

    private func previewOriginal() {
        downloading = true
        Task {
            defer { downloading = false }
            do {
                let url = try await store.downloadOriginal(for: item)
                previewURL = url
                guard QLPreviewController.canPreview(url as NSURL) else {
                    errorMessage = "This format has no built-in preview. Use Share original to open it in another app."
                    return
                }
                showOriginal = true
            } catch { errorMessage = "Couldn’t retrieve the original. \(error.localizedDescription)" }
        }
    }
}
