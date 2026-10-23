import Foundation
import SwiftData
import BookmarkCloud

@Model
final class PendingOperation {
    @Attribute(.unique) var id: UUID
    var scopeID: String
    var entity: String
    var entityID: UUID
    var payload: Data
    var createdAt: Date
    var attempted: Bool
    var blocked: Bool
    var conflict: Data?
    var migrationSourceKey: String?

    init(_ operation: CloudOperation, scopeID: String, migrationSourceKey: String? = nil) throws {
        id = operation.operationID
        self.scopeID = scopeID
        entity = operation.entity
        entityID = operation.id
        payload = try JSONEncoder().encode(operation)
        createdAt = Date()
        attempted = false
        blocked = false
        self.migrationSourceKey = migrationSourceKey
    }

    func operation() throws -> CloudOperation { try JSONDecoder().decode(CloudOperation.self, from: payload) }
}
