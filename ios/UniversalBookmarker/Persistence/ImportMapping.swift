import Foundation
import SwiftData

@Model
final class ImportMapping {
    @Attribute(.unique) var key: String
    var targetID: UUID

    init(key: String, targetID: UUID) {
        self.key = key
        self.targetID = targetID
    }
}
