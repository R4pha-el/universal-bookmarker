import Foundation

public struct BookmarkItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var kind: BookmarkKind
    public var url: URL?
    public var filename: String?
    public var localFileName: String?
    public var contentType: String?
    public var byteCount: Int?
    public var note: String
    public var collectionID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var version: Int64
    public var scopeID: String
    public var syncStatus: SyncStatus

    /// New values are local, unversioned, uncollected, and device scoped.
    public init(id: UUID = UUID(), title: String, kind: BookmarkKind, url: URL? = nil,
                filename: String? = nil, localFileName: String? = nil,
                contentType: String? = nil, byteCount: Int? = nil, note: String = "",
                collectionID: UUID? = nil, createdAt: Date = Date(), updatedAt: Date? = nil,
                deletedAt: Date? = nil, version: Int64 = 0,
                scopeID: String = LibraryScope.device.id, syncStatus: SyncStatus = .local) {
        self.id = id
        self.title = title
        self.kind = kind
        self.url = url
        self.filename = filename
        self.localFileName = localFileName
        self.contentType = contentType
        self.byteCount = byteCount
        self.note = note
        self.collectionID = collectionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.version = version
        self.scopeID = scopeID
        self.syncStatus = syncStatus
    }
}
