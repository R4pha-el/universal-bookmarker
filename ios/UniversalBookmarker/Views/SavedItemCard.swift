import SwiftUI
import BookmarkCore

struct SavedItemCard: View {
    let item: BookmarkItem
    let fileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.kind == .photo, fileURL != nil {
                ItemArtwork(item: item, fileURL: fileURL)
                    .frame(height: 130)
            } else {
                Image(systemName: LibraryDesign.symbol(item.kind))
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.tint.opacity(0.1), in: .rect(cornerRadius: 13))
                    .accessibilityHidden(true)
            }
            Text(item.title).font(.headline).lineLimit(3).multilineTextAlignment(.leading)
            Text(LibraryDesign.source(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .topLeading)
        .padding(LibraryDesign.spacing)
        .background(.background, in: .rect(cornerRadius: LibraryDesign.corner))
        .overlay(RoundedRectangle(cornerRadius: LibraryDesign.corner).stroke(.quaternary))
        .contentShape(.rect(cornerRadius: LibraryDesign.corner))
        .accessibilityElement(children: .combine)
    }
}
