import SwiftUI
import BookmarkCore

struct LibraryView: View {
    let store: LibraryStore
    var collectionID: UUID?
    var title = "Library"
    var onAdd: (() -> Void)?
    @State private var filter = LibraryFilter.all
    @AppStorage("library.showGrid") private var showGrid = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var items: [BookmarkItem] {
        store.items.filter {
            $0.deletedAt == nil && filter.includes($0)
                && (collectionID == nil || $0.collectionID == collectionID)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private var groupedItems: [(date: Date, items: [BookmarkItem])] {
        let groups = Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryFilterPicker(selection: $filter)
                .padding(.horizontal, LibraryDesign.inset).padding(.vertical, 10)
            if items.isEmpty {
                ContentUnavailableView {
                    Label(filter == .all ? "Your library starts here" : "No saved \(filter.rawValue.lowercased())", systemImage: "bookmark")
                } description: {
                    Text(collectionID == nil ? "Keep links, photos, and files together. Collections are always optional." : "Move saved items here from their details.")
                } actions: {
                    if let onAdd { Button("Add to library", systemImage: "plus", action: onAdd).buttonStyle(.borderedProminent) }
                }
            } else if showGrid && !dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: LibraryDesign.spacing) {
                        ForEach(items) { item in
                            NavigationLink {
                                ItemDetailView(store: store, item: item)
                            } label: {
                                SavedItemCard(item: item, fileURL: store.fileURL(for: item))
                            }
                            .buttonStyle(.plain)
                            .modifier(ItemActionsModifier(store: store, item: item))
                        }
                    }.padding(LibraryDesign.inset)
                }
            } else {
                List {
                    ForEach(groupedItems, id: \.date) { group in
                        Section {
                            ForEach(group.items) { item in
                                NavigationLink {
                                    ItemDetailView(store: store, item: item)
                                } label: {
                                    SavedItemRow(item: item, fileURL: store.fileURL(for: item))
                                }
                                .modifier(ItemActionsModifier(store: store, item: item))
                            }
                        } header: {
                            Text(group.date, format: .dateTime.month(.wide).day().year())
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showGrid ? "Show list" : "Show grid", systemImage: showGrid ? "list.bullet" : "square.grid.2x2") {
                    showGrid.toggle()
                }
                .accessibilityIdentifier("library.layout")
            }
        }
        .refreshable { await store.retrySync() }
    }
}
