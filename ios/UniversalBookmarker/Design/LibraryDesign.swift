import SwiftUI
import BookmarkCore

enum LibraryDesign {
    static let spacing: CGFloat = 16
    static let corner: CGFloat = 22
    static let inset: CGFloat = 20

    static func tint(_ name: String) -> Color {
        switch name {
        case "rose": .pink
        case "peach": .orange
        case "mint": .mint
        case "blue": .blue
        case "lavender": .purple
        default: .indigo
        }
    }

    static func symbol(_ kind: BookmarkKind) -> String {
        switch kind {
        case .link: "link"
        case .photo: "photo"
        case .pdf: "doc.richtext"
        case .file: "doc"
        }
    }

    static func source(_ item: BookmarkItem) -> String {
        switch item.kind {
        case .link: item.url?.host() ?? "Link"
        case .photo: "Photo"
        case .pdf: "PDF document"
        case .file: item.filename ?? "File"
        }
    }
}
