import SwiftUI
import BookmarkCore

struct CollectionsView: View {
    let store: LibraryStore
    @State private var showCreate = false
    @State private var editing: BookmarkCollection?
    @State private var deleting: BookmarkCollection?
    @State private var errorMessage: String?
    @AppStorage("collections.showGrid") private var showGrid = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var collections: [BookmarkCollection] {
        store.collections.filter { $0.deletedAt == nil }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if collections.isEmpty {
                ContentUnavailableView {
                    Label("A little room for everything", systemImage: "folder")
                } description: {
                    Text("Create a collection when you need one. Every save stays in your library.")
                } actions: {
                    Button("New collection", systemImage: "folder.badge.plus") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if showGrid && !dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 28) {
                        ForEach(collections) { collection in
                            NavigationLink {
                                LibraryView(store: store, collectionID: collection.id, title: collection.name)
                            } label: {
                                FolderCard(collection: collection, items: items(in: collection))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { editing = collection }
                                Button("Delete collection", systemImage: "trash", role: .destructive) { deleting = collection }
                            }
                        }
                    }.padding(LibraryDesign.inset)
                }
            } else {
                List(collections) { collection in
                    NavigationLink {
                        LibraryView(store: store, collectionID: collection.id, title: collection.name)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(collection.name).font(.headline)
                                Text("\(items(in: collection).count) items").font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder.fill").foregroundStyle(LibraryDesign.tint(collection.tint))
                        }.padding(.vertical, 6)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { deleting = collection }
                        Button("Rename") { editing = collection }.tint(.blue)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editing = collection }
                        Button("Delete collection", systemImage: "trash", role: .destructive) { deleting = collection }
                    }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(showGrid ? "Show list" : "Show grid", systemImage: showGrid ? "list.bullet" : "square.grid.2x2") { showGrid.toggle() }
                Button("New collection", systemImage: "folder.badge.plus") { showCreate = true }
                    .accessibilityIdentifier("collection.create")
            }
        }
        .sheet(isPresented: $showCreate) {
            CollectionEditorView { name, tint in try store.createCollection(name: name, tint: tint) }
        }
        .sheet(item: $editing) { collection in
            CollectionEditorView(name: collection.name, tint: collection.tint, isRenaming: true) { name, _ in
                try store.renameCollection(collection, name: name)
            }
        }
        .confirmationDialog("Delete collection?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete collection", role: .destructive, action: deleteCollection)
        } message: {
            Text("Its items will stay in your library.")
        }
        .alert("Couldn’t update collection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {} message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private func items(in collection: BookmarkCollection) -> [BookmarkItem] {
        store.items.filter { $0.collectionID == collection.id && $0.deletedAt == nil }
    }

    private func deleteCollection() {
        guard let deleting else { return }
        do { try store.deleteCollection(deleting); self.deleting = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
