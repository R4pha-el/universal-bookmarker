import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import BookmarkCloud

private actor RecordingTransport: HTTPTransport {
    private var responses: [HTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [HTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
private let itemID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
private let attachmentID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
private let hash = String(repeating: "a", count: 64)
private var session: AuthSession {
    AuthSession(accessToken: "test-jwt", refreshToken: "refresh-value", expiresAt: Date().addingTimeInterval(3600), userID: owner, email: "a@example.test")
}
private var storagePath: String { "\(owner.uuidString.lowercased())/\(itemID.uuidString.lowercased())/\(attachmentID.uuidString.lowercased())" }
private func response(_ body: String = "{}", status: Int = 200) -> HTTPResponse {
    HTTPResponse(data: Data(body.utf8), statusCode: status)
}
private func client(_ transport: RecordingTransport, url: String = "https://project.example.test") -> BackendClient {
    BackendClient(configuration: BackendConfiguration(url: URL(string: url)!, publishableKey: "publishable-test"), transport: transport)
}
private func object(_ data: Data?) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: #require(data)) as! [String: Any]
}
private func withOriginal(_ action: (URL) async throws -> Void) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("original bytes".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try await action(url)
}

@Test func requestsEmailCodeWithoutCredentialsInBody() async throws {
    let transport = RecordingTransport([response()])
    try await client(transport).requestCode(email: "a@example.test")
    let request = try #require(await transport.requests.first)
    #expect(request.url?.absoluteString == "https://project.example.test/auth/v1/otp")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "apikey") == "publishable-test")
    let body = try object(request.httpBody)
    #expect(body["email"] as? String == "a@example.test")
    #expect(body["create_user"] as? Bool == true)
    #expect(body["accessToken"] == nil)
}

@Test func verifiesCodeAndDecodesSessionExpiry() async throws {
    let transport = RecordingTransport([response("""
    {"access_token":"new-jwt","refresh_token":"new-refresh","expires_at":2000000000,"user":{"id":"\(owner)","email":"a@example.test"}}
    """)])
    let result = try await client(transport).verifyCode(email: "a@example.test", code: "123456")
    #expect(result.accessToken == "new-jwt")
    #expect(result.refreshToken == "new-refresh")
    #expect(result.userID == owner)
    #expect(result.expiresAt == Date(timeIntervalSince1970: 2_000_000_000))
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/auth/v1/verify")
    let body = try object(request.httpBody)
    #expect(body["type"] as? String == "email")
    #expect(body["token"] as? String == "123456")
}

@Test func refreshUsesRefreshGrantAndRelativeExpiry() async throws {
    let before = Date()
    let transport = RecordingTransport([response("""
    {"access_token":"refreshed","refresh_token":"next","expires_in":3600,"user":{"id":"\(owner)"}}
    """)])
    let result = try await client(transport).refresh(refreshToken: "previous")
    #expect(result.expiresAt.timeIntervalSince(before) >= 3599)
    #expect(result.expiresAt.timeIntervalSince(before) < 3605)
    let request = try #require(await transport.requests.first)
    #expect(request.url?.query == "grant_type=refresh_token")
    #expect(try object(request.httpBody)["refresh_token"] as? String == "previous")
}

@Test func authenticatedLogoutAndDeletionUseCorrectEndpoints() async throws {
    let transport = RecordingTransport([response(status: 204), response(status: 204)])
    let backend = client(transport)
    try await backend.signOut(accessToken: "test-jwt")
    try await backend.deleteAccount(session: session)
    let requests = await transport.requests
    #expect(requests.map { $0.url!.path } == ["/auth/v1/logout", "/functions/v1/delete-account"])
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer test-jwt" })
}

@Test func applyPreservesOperationIdentityAndConflictRecord() async throws {
    let transport = RecordingTransport([response("""
    {"status":"conflict","code":"version_conflict","record":{"version":4,"title":"server title"},"revision":9,"warnings":["collection_removed"]}
    """)])
    let operation = CloudOperation(operationID: UUID(), entity: "item", action: "upsert", id: itemID, expectedVersion: 3, payload: ["title": .string("local title"), "collectionID": .null])
    let outcome = try await client(transport).apply(operation, session: session)
    #expect(outcome.status == "conflict")
    #expect(outcome.record?["version"] == .number(4))
    #expect(outcome.revision == 9)
    #expect(outcome.warnings == ["collection_removed"])
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/rest/v1/rpc/apply_operation")
    let sent = try #require(try object(request.httpBody)["operation"] as? [String: Any])
    #expect((sent["operationID"] as? String)?.lowercased() == operation.operationID.uuidString.lowercased())
    #expect(sent["expectedVersion"] as? Int == 3)
    #expect((sent["payload"] as? [String: Any])?["title"] as? String == "local title")
}

@Test func changesDecodeOrderedCursorAndUseBoundedPageSize() async throws {
    let transport = RecordingTransport([response("""
    {"changes":[{"revision":12,"entity":"item","id":"\(itemID)","record":{"title":"Saved","deletedAt":null}}],"nextRevision":12,"hasMore":true}
    """)])
    let page = try await client(transport).changes(afterRevision: 11, session: session)
    #expect(page.nextRevision == 12)
    #expect(page.hasMore)
    #expect(page.changes.first?.record["deletedAt"] == .null)
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/rest/v1/rpc/library_changes")
    #expect(try object(request.httpBody)["after_revision"] as? Int == 11)
    #expect(try object(request.httpBody)["page_size"] as? Int == 200)
}

@Test func unauthorizedResponseIsTypedAndOmitsSensitiveBody() async throws {
    let transport = RecordingTransport([response("{\"message\":\"secret-token-must-not-leak\"}", status: 401)])
    do {
        try await client(transport).requestCode(email: "a@example.test")
        Issue.record("Expected unauthorized")
    } catch let error as BackendError {
        #expect(error == .unauthorized)
        #expect(!String(describing: error).contains("secret-token"))
    }
}

@Test func expiredSessionDoesNotTransmit() async throws {
    let transport = RecordingTransport([])
    let expired = AuthSession(accessToken: "expired", refreshToken: "refresh", expiresAt: .distantPast, userID: owner, email: nil)
    do {
        _ = try await client(transport).changes(afterRevision: 0, session: expired)
        Issue.record("Expected expiry")
    } catch let error as BackendError { #expect(error == .sessionExpired) }
    #expect(await transport.requests.isEmpty)
}

@Test func rejectsInsecureRemoteBackendBeforeTransport() async throws {
    let transport = RecordingTransport([])
    do {
        try await client(transport, url: "http://remote.example.test").requestCode(email: "a@example.test")
        Issue.record("Expected configuration rejection")
    } catch let error as BackendError { #expect(error == .invalidConfiguration) }
    #expect(await transport.requests.isEmpty)
}

@Test func allowsLocalHTTPDevelopmentBackend() async throws {
    let transport = RecordingTransport([response()])
    try await client(transport, url: "http://127.0.0.1:54321").requestCode(email: "a@example.test")
    #expect(await transport.requests.count == 1)
}

@Test func uploadUsesCreateOnlyAndHashMetadata() async throws {
    let transport = RecordingTransport([response()])
    try await withOriginal { url in
        try await client(transport).uploadOriginal(fileURL: url, path: storagePath, contentType: "image/png", sha256: hash, session: session)
    }
    let request = try #require(await transport.requests.first)
    #expect(request.url?.path == "/storage/v1/object/originals/\(storagePath)")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-upsert") == "false")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
    #expect(request.httpBody == Data("original bytes".utf8))
    let metadata = try #require(request.value(forHTTPHeaderField: "x-metadata"))
    #expect(try object(Data(base64Encoded: metadata))["sha256"] as? String == hash)
}

@Test func duplicateUploadAcceptsOnlyAuthenticatedExactBytes() async throws {
    let transport = RecordingTransport([response(status: 409), HTTPResponse(data: Data("original bytes".utf8), statusCode: 200)])
    try await withOriginal { url in
        try await client(transport).uploadOriginal(fileURL: url, path: storagePath, contentType: "image/png", sha256: hash, session: session)
    }
    let requests = await transport.requests
    #expect(requests.count == 2)
    #expect(requests[1].httpMethod == "GET")
    #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer test-jwt")
}

@Test func duplicateUploadWithDifferentBytesIsActionableError() async throws {
    let transport = RecordingTransport([response(status: 409), response("different bytes")])
    try await withOriginal { url in
        do {
            try await client(transport).uploadOriginal(fileURL: url, path: storagePath, contentType: "image/png", sha256: hash, session: session)
            Issue.record("Expected immutable mismatch")
        } catch let error as BackendError { #expect(error == .originalMismatch) }
    }
    #expect(await transport.requests.count == 2)
}

@Test func storagePathRejectsTraversalCrossOwnerAndEncodedSlash() async throws {
    let transport = RecordingTransport([])
    for path in ["../bad/file", "\(UUID())/\(itemID)/\(attachmentID)", "\(owner)/a%2Fb/\(attachmentID)", "\(owner)//\(attachmentID)"] {
        do {
            _ = try await client(transport).downloadOriginal(path: path, session: session)
            Issue.record("Expected path rejection")
        } catch let error as BackendError { #expect(error == .invalidStoragePath) }
    }
    #expect(await transport.requests.isEmpty)
}

@Test func originalDownloadRetainsBytes() async throws {
    let bytes = Data([0, 255, 1, 15])
    let transport = RecordingTransport([HTTPResponse(data: bytes, statusCode: 200)])
    let actual = try await client(transport).downloadOriginal(path: storagePath, session: session)
    #expect(actual == bytes)
}

@Test func jsonAndSessionRoundTripAndFractionalDates() throws {
    let value: JSONValue = .object(["array": .array([.number(1.5), .bool(true), .null, .string("hello")])])
    let currentSession = session
    #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
    #expect(try JSONDecoder().decode(AuthSession.self, from: JSONEncoder().encode(currentSession)) == currentSession)
    let fractional = try #require(BackendDate.parse("2026-10-23T10:20:30.123Z"))
    #expect(BackendDate.parse(BackendDate.string(fractional)) != nil)
    #expect(BackendDate.parse("2026-10-23T10:20:30Z") != nil)
    #expect(BackendDate.parse("not-a-date") == nil)
}

@Test func serverErrorsRetainStatusWithoutResponseContent() async throws {
    let transport = RecordingTransport([response("backend-secret-and-user-data", status: 503)])
    do {
        _ = try await client(transport).changes(afterRevision: 0, session: session)
        Issue.record("Expected backend failure")
    } catch let error as BackendError {
        #expect(error == .httpStatus(503))
        #expect(!error.localizedDescription.contains("backend-secret"))
    }
}

@Test func malformedAuthAndRPCResponsesAreTyped() async throws {
    let transport = RecordingTransport([response("{}"), response("not-json")])
    let backend = client(transport)
    do {
        _ = try await backend.verifyCode(email: "a@example.test", code: "123456")
        Issue.record("Expected malformed auth rejection")
    } catch let error as BackendError { #expect(error == .invalidResponse) }
    do {
        _ = try await backend.changes(afterRevision: 0, session: session)
        Issue.record("Expected malformed change rejection")
    } catch let error as BackendError { #expect(error == .invalidResponse) }
}

@Test func invalidOperationDoesNotTransmit() async throws {
    let transport = RecordingTransport([])
    let operation = CloudOperation(operationID: UUID(), entity: "unknown", action: "upsert", id: itemID, expectedVersion: -1, payload: [:])
    do {
        _ = try await client(transport).apply(operation, session: session)
        Issue.record("Expected invalid operation rejection")
    } catch let error as BackendError { #expect(error == .invalidOperation) }
    #expect(await transport.requests.isEmpty)
}

@Test func invalidOriginalHashDoesNotTransmit() async throws {
    let transport = RecordingTransport([])
    try await withOriginal { url in
        do {
            try await client(transport).uploadOriginal(fileURL: url, path: storagePath, contentType: "image/png", sha256: "not-a-sha256", session: session)
            Issue.record("Expected invalid checksum rejection")
        } catch let error as BackendError { #expect(error == .invalidOriginal) }
    }
    #expect(await transport.requests.isEmpty)
}

@Test func failedDuplicateVerificationRemainsFailure() async throws {
    let transport = RecordingTransport([response(status: 409), response(status: 403)])
    try await withOriginal { url in
        do {
            try await client(transport).uploadOriginal(fileURL: url, path: storagePath, contentType: "image/png", sha256: hash, session: session)
            Issue.record("Expected failed verification")
        } catch let error as BackendError { #expect(error == .unauthorized) }
    }
    #expect(await transport.requests.count == 2)
}
