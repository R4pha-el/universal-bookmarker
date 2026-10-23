import Foundation

public struct BookmarkCollection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var tint: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var version: Int64
    public var scopeID: String

    public init(id: UUID = UUID(), name: String, tint: String = "blue", createdAt: Date = Date(),
                updatedAt: Date? = nil, deletedAt: Date? = nil, version: Int64 = 0,
                scopeID: String = LibraryScope.device.id) {
        self.id = id
        self.name = name
        self.tint = tint
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.version = version
        self.scopeID = scopeID
    }
}
