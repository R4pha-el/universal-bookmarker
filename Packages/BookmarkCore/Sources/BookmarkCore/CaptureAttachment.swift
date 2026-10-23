import Foundation

public struct CaptureAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: BookmarkKind
    public var filename: String
    public var localFileName: String
    public var contentType: String?
    public var byteCount: Int

    public init(id: UUID = UUID(), kind: BookmarkKind, filename: String,
                localFileName: String, contentType: String? = nil, byteCount: Int) {
        self.id = id
        self.kind = kind
        self.filename = filename
        self.localFileName = localFileName
        self.contentType = contentType
        self.byteCount = byteCount
    }
}
