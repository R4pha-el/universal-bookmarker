import SwiftUI
import BookmarkCore

struct SearchView: View {
    let store: LibraryStore
    @State private var query = ""
    @State private var filter = LibraryFilter.all
    @FocusState private var focused: Bool

    private var results: [BookmarkItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return store.items.filter {
            $0.deletedAt == nil && filter.includes($0) && LibrarySearch.matches($0, query: query)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search your library", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("search.field")
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(.quaternary, in: .rect(cornerRadius: 14))
            .padding(.horizontal, LibraryDesign.inset)
            LibraryFilterPicker(selection: $filter).padding(LibraryDesign.inset)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Find something you saved", systemImage: "magnifyingglass", description: Text("Search titles, websites, filenames, and your notes across this library."))
            } else if results.isEmpty {
                ContentUnavailableView {
                    Label("No matching saves", systemImage: "magnifyingglass")
                } description: {
                    Text("Try another phrase or show all item types.")
                } actions: {
                    Button("Clear search and filters") { query = ""; filter = .all; focused = true }
                }
            } else {
                List {
                    Section("\(results.count) results · Entire library") {
                        ForEach(results) { item in
                            NavigationLink {
                                ItemDetailView(store: store, item: item)
                            } label: {
                                SavedItemRow(item: item, fileURL: store.fileURL(for: item))
                            }
                            .modifier(ItemActionsModifier(store: store, item: item))
                        }
                    }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("Search")
        .onAppear { focused = true }
    }
}
