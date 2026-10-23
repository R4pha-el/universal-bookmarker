import SwiftUI
import BookmarkCore

struct ItemActionsModifier: ViewModifier {
    let store: LibraryStore
    let item: BookmarkItem
    @State private var showEdit = false
    @State private var showDelete = false
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Rename", systemImage: "pencil") { showEdit = true }
                Menu("Move to collection", systemImage: "folder") {
                    Button("No collection") { move(to: nil) }
                    ForEach(store.collections.filter { $0.deletedAt == nil }) { collection in
                        Button(collection.name) { move(to: collection.id) }
                    }
                }
                if let url = item.url ?? store.fileURL(for: item) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Delete", systemImage: "trash", role: .destructive) { showDelete = true }
            }
            .sheet(isPresented: $showEdit) {
                NavigationStack {
                    ItemDetailView(store: store, item: item)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showEdit = false }
                            }
                        }
                }
            }
            .confirmationDialog("Delete this item?", isPresented: $showDelete, titleVisibility: .visible) {
                Button("Delete item", role: .destructive) {
                    do { try store.deleteItem(item) }
                    catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("Couldn’t update item", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {} message: {
                Text(errorMessage ?? "Please try again.")
            }
    }

    private func move(to collectionID: UUID?) {
        do { try store.moveItem(item, to: collectionID) }
        catch { errorMessage = error.localizedDescription }
    }
}
