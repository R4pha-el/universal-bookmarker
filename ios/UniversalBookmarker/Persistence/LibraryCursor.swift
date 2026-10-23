import Foundation
import SwiftData

@Model
final class LibraryCursor {
    @Attribute(.unique) var scopeID: String
    var revision: Int64

    init(scopeID: String, revision: Int64 = 0) {
        self.scopeID = scopeID
        self.revision = revision
    }
}
