import BookmarkCore

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "All", links = "Links", photos = "Photos", files = "Files"
    var id: String { rawValue }

    func includes(_ item: BookmarkItem) -> Bool {
        switch self {
        case .all: true
        case .links: item.kind == .link
        case .photos: item.kind == .photo
        case .files: item.kind == .file || item.kind == .pdf
        }
    }
}
