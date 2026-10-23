import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var data: Data
    public var statusCode: Int
    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        return HTTPResponse(data: data, statusCode: response.statusCode)
    }
}

public actor BackendClient {
    private let configuration: BackendConfiguration
    private let transport: any HTTPTransport
    private let maxOriginalBytes = 25 * 1_024 * 1_024

    public init(configuration: BackendConfiguration, transport: any HTTPTransport = URLSessionTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    public func requestCode(email: String) async throws {
        _ = try await jsonRequest("auth/v1/otp", body: ["email": .string(email), "create_user": .bool(true)])
    }

    public func verifyCode(email: String, code: String) async throws -> AuthSession {
        let data = try await jsonRequest("auth/v1/verify", body: ["email": .string(email), "token": .string(code), "type": .string("email")])
        return try decodeAuth(data)
    }

    public func refresh(refreshToken: String) async throws -> AuthSession {
        let data = try await jsonRequest("auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: ["refresh_token": .string(refreshToken)])
        return try decodeAuth(data)
    }

    public func signOut(accessToken: String) async throws {
        _ = try await jsonRequest("auth/v1/logout", body: [:], accessToken: accessToken)
    }

    public func deleteAccount(session: AuthSession) async throws {
        try validate(session)
        _ = try await jsonRequest("functions/v1/delete-account", body: [:], accessToken: session.accessToken)
    }

    public func cleanupOriginals(session: AuthSession) async throws {
        try validate(session)
        _ = try await jsonRequest("functions/v1/cleanup-originals", body: [:], accessToken: session.accessToken)
    }

    public func apply(_ operation: CloudOperation, session: AuthSession) async throws -> CloudOutcome {
        try validate(session)
        guard ["item", "collection"].contains(operation.entity), ["upsert", "delete"].contains(operation.action), operation.expectedVersion >= 0 else {
            throw BackendError.invalidOperation
        }
        let body: Data
        do { body = try JSONEncoder().encode(OperationEnvelope(operation: operation)) }
        catch { throw BackendError.invalidOperation }
        let request = try makeRequest("rest/v1/rpc/apply_operation", method: "POST", body: body, accessToken: session.accessToken)
        return try decode(CloudOutcome.self, from: await send(request))
    }

    public func changes(afterRevision: Int64, session: AuthSession) async throws -> CloudChangePage {
        try validate(session)
        guard afterRevision >= 0 else { throw BackendError.invalidOperation }
        // Encode integer cursors directly to preserve Int64 precision.
        let body = try JSONEncoder().encode(ChangeQuery(after_revision: afterRevision, page_size: 200))
        let request = try makeRequest("rest/v1/rpc/library_changes", method: "POST", body: body, accessToken: session.accessToken)
        return try decode(CloudChangePage.self, from: await send(request))
    }

    public func uploadOriginal(fileURL: URL, path: String, contentType: String, sha256: String, session: AuthSession) async throws {
        try validate(session)
        try validateStoragePath(path, session: session)
        guard fileURL.isFileURL,
              sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              !contentType.isEmpty, !contentType.contains("\r"), !contentType.contains("\n") else {
            throw BackendError.invalidOriginal
        }
        let attributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size <= maxOriginalBytes else { throw BackendError.invalidOriginal }
        // Take one in-memory snapshot so a retry comparison uses the exact transmitted bytes.
        let original = try Data(contentsOf: fileURL)
        guard original.count <= maxOriginalBytes else { throw BackendError.invalidOriginal }
        var request = try makeRequest("storage/v1/object/originals/\(path)", method: "POST", body: original, accessToken: session.accessToken)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        let metadata = try JSONEncoder().encode(["sha256": sha256.lowercased()])
        request.setValue(metadata.base64EncodedString(), forHTTPHeaderField: "x-metadata")
        let response = try await transport.send(request)
        if response.statusCode == 409 {
            let remote = try await downloadOriginal(path: path, session: session)
            guard original == remote else { throw BackendError.originalMismatch }
            return
        }
        try validateResponse(response)
    }

    public func downloadOriginal(path: String, session: AuthSession) async throws -> Data {
        try validate(session)
        try validateStoragePath(path, session: session)
        let request = try makeRequest("storage/v1/object/originals/\(path)", method: "GET", accessToken: session.accessToken)
        return try await send(request)
    }

    private func validate(_ session: AuthSession) throws {
        guard session.expiresAt > Date() else { throw BackendError.sessionExpired }
        guard !session.accessToken.isEmpty else { throw BackendError.unauthorized }
    }

    private func validateStoragePath(_ path: String, session: AuthSession) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ UUID(uuidString: String($0)) != nil }),
              UUID(uuidString: String(components[0])) == session.userID else {
            throw BackendError.invalidStoragePath
        }
    }

    private func jsonRequest(_ path: String, query: [URLQueryItem] = [], body: [String: JSONValue], accessToken: String? = nil) async throws -> Data {
        let data = try JSONEncoder().encode(body)
        let request = try makeRequest(path, query: query, method: "POST", body: data, accessToken: accessToken)
        return try await send(request)
    }

    private func makeRequest(_ path: String, query: [URLQueryItem] = [], method: String, body: Data? = nil, accessToken: String? = nil) throws -> URLRequest {
        let base = configuration.url
        let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
        let secure = base.scheme?.lowercased() == "https"
        let localHTTP = base.scheme?.lowercased() == "http" && localHosts.contains(base.host?.lowercased() ?? "")
        guard secure || localHTTP, base.host != nil, base.user == nil, base.password == nil,
              base.query == nil, base.fragment == nil,
              !configuration.publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !configuration.publishableKey.contains("\r"), !configuration.publishableKey.contains("\n") else {
            throw BackendError.invalidConfiguration
        }
        let endpoint = base.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw BackendError.invalidConfiguration }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BackendError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            guard !accessToken.isEmpty, !accessToken.contains("\r"), !accessToken.contains("\n") else { throw BackendError.unauthorized }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let response = try await transport.send(request)
        try validateResponse(response)
        return response.data
    }

    private func validateResponse(_ response: HTTPResponse) throws {
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 { throw BackendError.unauthorized }
            throw BackendError.httpStatus(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw BackendError.invalidResponse }
    }

    private func decodeAuth(_ data: Data) throws -> AuthSession {
        let wire = try decode(AuthResponse.self, from: data)
        let expiry: Date
        if let absolute = wire.expires_at, absolute.isFinite { expiry = Date(timeIntervalSince1970: absolute) }
        else if let relative = wire.expires_in, relative.isFinite { expiry = Date().addingTimeInterval(relative) }
        else { throw BackendError.invalidResponse }
        guard !wire.access_token.isEmpty, !wire.refresh_token.isEmpty, expiry > Date() else { throw BackendError.invalidResponse }
        return AuthSession(accessToken: wire.access_token, refreshToken: wire.refresh_token, expiresAt: expiry, userID: wire.user.id, email: wire.user.email)
    }
}

private struct OperationEnvelope: Encodable { let operation: CloudOperation }
private struct ChangeQuery: Encodable { let after_revision: Int64; let page_size: Int }
private struct AuthResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_at: Double?
    let expires_in: Double?
    let user: User
    struct User: Decodable { let id: UUID; let email: String? }
}
