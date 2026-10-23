import Foundation

public enum LibraryFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case all, links, photos, files
    public var id: String { rawValue }
}
