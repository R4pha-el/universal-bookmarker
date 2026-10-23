import SwiftUI
import BookmarkCore

struct ItemArtwork: View {
    let item: BookmarkItem
    let fileURL: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(.quaternary)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: LibraryDesign.symbol(item.kind))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .clipShape(.rect(cornerRadius: 15))
        .accessibilityHidden(true)
        .task(id: fileURL) {
            if item.kind == .photo, let fileURL {
                let data = await PhotoThumbnailLoader.shared.data(for: fileURL)
                guard !Task.isCancelled else { return }
                image = data.flatMap { UIImage(data: $0) }
            } else {
                image = nil
            }
        }
    }
}
