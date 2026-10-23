import Foundation

public struct BackendConfiguration: Sendable {
    public let url: URL
    public let publishableKey: String
    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }
}

public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: UUID
    public var email: String?
    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: UUID, email: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userID = userID
        self.email = email
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), null, array([JSONValue]), object([String: JSONValue])
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct CloudOperation: Codable, Sendable, Equatable {
    public var operationID: UUID
    public var entity: String
    public var action: String
    public var id: UUID
    public var expectedVersion: Int64
    public var payload: [String: JSONValue]
    public init(operationID: UUID, entity: String, action: String, id: UUID, expectedVersion: Int64, payload: [String: JSONValue]) {
        self.operationID = operationID
        self.entity = entity
        self.action = action
        self.id = id
        self.expectedVersion = expectedVersion
        self.payload = payload
    }
}

public struct CloudOutcome: Codable, Sendable, Equatable {
    public var status: String
    public var code: String?
    public var record: [String: JSONValue]?
    public var revision: Int64?
    public var warnings: [String]?
    public init(status: String, code: String? = nil, record: [String: JSONValue]? = nil, revision: Int64? = nil, warnings: [String]? = nil) {
        self.status = status
        self.code = code
        self.record = record
        self.revision = revision
        self.warnings = warnings
    }
}

public struct CloudChange: Codable, Sendable, Equatable {
    public var revision: Int64
    public var entity: String
    public var id: UUID
    public var record: [String: JSONValue]
    public init(revision: Int64, entity: String, id: UUID, record: [String: JSONValue]) {
        self.revision = revision
        self.entity = entity
        self.id = id
        self.record = record
    }
}

public struct CloudChangePage: Codable, Sendable, Equatable {
    public var changes: [CloudChange]
    public var nextRevision: Int64
    public var hasMore: Bool
    public init(changes: [CloudChange], nextRevision: Int64, hasMore: Bool) {
        self.changes = changes
        self.nextRevision = nextRevision
        self.hasMore = hasMore
    }
}

public enum BackendError: Error, Sendable, Equatable, LocalizedError {
    case invalidConfiguration, invalidResponse, unauthorized, sessionExpired, invalidStoragePath, originalMismatch, invalidOriginal, invalidOperation
    case httpStatus(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Configure a secure backend URL and publishable key."
        case .invalidResponse: "The sync service returned an invalid response."
        case .unauthorized: "Sign in again to connect sync."
        case .sessionExpired: "Your session expired. Refresh it to continue syncing."
        case .invalidStoragePath: "The original file path does not belong to this account."
        case .originalMismatch: "The existing original differs from this file. Keep this original and retry with a new attachment."
        case .invalidOriginal: "The original file or its checksum is invalid."
        case .invalidOperation: "The queued sync operation is invalid."
        case .httpStatus(let status): "The sync service returned HTTP \(status). Try again."
        }
    }
}

public enum BackendDate {
    public static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    public static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
