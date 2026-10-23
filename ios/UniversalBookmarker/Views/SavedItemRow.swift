import SwiftUI
import BookmarkCore

struct SavedItemRow: View {
    let item: BookmarkItem
    let fileURL: URL?

    var body: some View {
        HStack(spacing: LibraryDesign.spacing) {
            ItemArtwork(item: item, fileURL: fileURL)
                .frame(width: 54, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline).lineLimit(2)
                Label(LibraryDesign.source(item), systemImage: LibraryDesign.symbol(item.kind))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
