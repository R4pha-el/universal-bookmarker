import Foundation

public struct CaptureManifest: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var destination: DestinationDescriptor
    public var title: String
    public var url: URL?
    public var note: String
    public var collectionID: UUID?
    public var attachments: [CaptureAttachment]
    public var createdAt: Date
    public var scopeID: String { destination.scopeID }

    public init(id: UUID = UUID(), destination: DestinationDescriptor, title: String,
                url: URL? = nil, note: String = "", collectionID: UUID? = nil,
                attachments: [CaptureAttachment] = [], createdAt: Date = Date()) {
        self.id = id
        self.destination = destination
        self.title = title
        self.url = url
        self.note = note
        self.collectionID = collectionID
        self.attachments = attachments
        self.createdAt = createdAt
    }
}
