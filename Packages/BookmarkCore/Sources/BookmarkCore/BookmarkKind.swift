import Foundation

public enum BookmarkKind: String, Codable, CaseIterable, Sendable {
    case link, photo, pdf, file

    public func isIncluded(in filter: LibraryFilter) -> Bool {
        switch filter {
        case .all: true
        case .links: self == .link
        case .photos: self == .photo
        case .files: self == .pdf || self == .file
        }
    }
}
