import SwiftUI
import BookmarkCore

struct FolderCard: View {
    let collection: BookmarkCollection
    let items: [BookmarkItem]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                FolderShape().fill(LibraryDesign.tint(collection.tint).opacity(colorScheme == .dark ? 0.42 : 0.25))
                RoundedRectangle(cornerRadius: 9)
                    .fill(.background)
                    .frame(width: 105, height: 90)
                    .rotationEffect(.degrees(-9)).offset(x: -10, y: -17)
                    .shadow(color: .black.opacity(0.06), radius: 4, y: -2)
                RoundedRectangle(cornerRadius: 9)
                    .fill(.background)
                    .frame(width: 102, height: 85)
                    .rotationEffect(.degrees(7)).offset(x: 13, y: -15)
                RoundedRectangle(cornerRadius: 17)
                    .fill(reduceTransparency ? AnyShapeStyle(LibraryDesign.tint(collection.tint).opacity(0.55)) : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 17).fill(LibraryDesign.tint(collection.tint).opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.4)))
                    .frame(height: 85)
                HStack(spacing: 5) {
                    ForEach(Array(Set(items.map { LibraryDesign.symbol($0.kind) })).sorted().prefix(3), id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.caption)
                            .frame(width: 27, height: 27)
                            .background(.background.opacity(0.85), in: .rect(cornerRadius: 8))
                    }
                    Spacer(minLength: 0)
                }.padding(12)
            }
            .frame(height: 130)
            .accessibilityHidden(true)
            Text(collection.name).font(.headline).lineLimit(2)
            Text("\(items.count) items").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
