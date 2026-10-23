import Foundation
import SwiftData
import BookmarkCore

@Model
final class StoredItem {
    @Attribute(.unique) var key: String
    var scopeID: String
    var payload: Data
    var attachmentID: String?
    var sha256: String?
    var storagePath: String?
    var originalUploaded: Bool = false

    init(_ item: BookmarkItem, attachmentID: String? = nil, sha256: String? = nil, storagePath: String? = nil) throws {
        key = Self.key(scopeID: item.scopeID, id: item.id)
        scopeID = item.scopeID
        payload = try JSONEncoder().encode(item)
        self.attachmentID = attachmentID
        self.sha256 = sha256
        self.storagePath = storagePath
    }

    static func key(scopeID: String, id: UUID) -> String { scopeID + "/" + id.uuidString.lowercased() }
    func value() throws -> BookmarkItem { try JSONDecoder().decode(BookmarkItem.self, from: payload) }
    func setValue(_ value: BookmarkItem) throws { payload = try JSONEncoder().encode(value) }
}
