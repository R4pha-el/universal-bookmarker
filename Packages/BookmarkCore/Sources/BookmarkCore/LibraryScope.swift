import Foundation

/// A stable, non-secret library identity; account scopes never reuse device scope.
public struct LibraryScope: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var accountID: UUID?

    public init(id: String, name: String, accountID: UUID? = nil) {
        self.id = id
        self.name = name
        self.accountID = accountID
    }

    public static let device = LibraryScope(id: "device", name: "On this iPhone")

    public static func account(userID: UUID) -> LibraryScope {
        LibraryScope(id: "account:\(userID.uuidString.lowercased())", name: "Account", accountID: userID)
    }
}
