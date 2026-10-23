import Foundation
import SwiftData
import BookmarkCore

@Model
final class StoredCollection {
    @Attribute(.unique) var key: String
    var scopeID: String
    var payload: Data

    init(_ collection: BookmarkCollection) throws {
        key = StoredItem.key(scopeID: collection.scopeID, id: collection.id)
        scopeID = collection.scopeID
        payload = try JSONEncoder().encode(collection)
    }

    func value() throws -> BookmarkCollection { try JSONDecoder().decode(BookmarkCollection.self, from: payload) }
    func setValue(_ value: BookmarkCollection) throws { payload = try JSONEncoder().encode(value) }
}
