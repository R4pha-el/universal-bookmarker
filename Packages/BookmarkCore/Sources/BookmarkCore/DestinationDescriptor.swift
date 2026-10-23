import Foundation

/// Snapshot at capture start; changing accounts later must not alter this value.
public struct DestinationDescriptor: Codable, Equatable, Sendable {
    public var scopeID: String
    public var generation: UUID
    public var updatedAt: Date

    public init(scopeID: String, generation: UUID = UUID(), updatedAt: Date = Date()) {
        self.scopeID = scopeID
        self.generation = generation
        self.updatedAt = updatedAt
    }
}
