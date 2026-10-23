# BookmarkCloud

Foundation-only Swift 6 client for Universal Bookmarker’s private Supabase API. No third-party dependencies. Supports iOS 17, macOS 14, and Linux (FoundationNetworking).

```swift
import BookmarkCloud

let backend = BackendClient(configuration: BackendConfiguration(
    url: URL(string: "https://YOUR_PROJECT.supabase.co")!,
    publishableKey: "YOUR_CLIENT_PUBLISHABLE_KEY"
))
try await backend.requestCode(email: "you@example.com")
let session = try await backend.verifyCode(email: "you@example.com", code: "123456")
let page = try await backend.changes(afterRevision: 0, session: session)
```

The application owns Keychain session storage, refresh scheduling, durable outbox/cursor storage, conflict presentation, and retries. The client does not log requests, credentials, email codes, or server response bodies. It never supplies service-role credentials. Configuration must use HTTPS; plain HTTP is accepted only for `localhost`, `127.0.0.1`, and `::1` development hosts. Invalid configuration fails before transmission.

## Public API

- `BackendConfiguration(url: URL, publishableKey: String)`
- `AuthSession(accessToken: String, refreshToken: String, expiresAt: Date, userID: UUID, email: String?)`: Codable, Sendable, Equatable. This is a local session value; direct Supabase snake-case auth responses are translated by the client.
- `BackendClient(configuration: BackendConfiguration, transport: any HTTPTransport = URLSessionTransport())`: actor.
- `requestCode(email:) async throws`
- `verifyCode(email:code:) async throws -> AuthSession`
- `refresh(refreshToken:) async throws -> AuthSession`
- `signOut(accessToken:) async throws`
- `deleteAccount(session:) async throws`
- `apply(_: CloudOperation, session:) async throws -> CloudOutcome`
- `changes(afterRevision: Int64, session:) async throws -> CloudChangePage`
- `uploadOriginal(fileURL:path:contentType:sha256:session:) async throws`
- `downloadOriginal(path:session:) async throws -> Data`
- `BackendDate.string(Date) -> String`, `BackendDate.parse(String) -> Date?`: PostgreSQL-compatible UTC ISO 8601, accepting timestamps with or without fractional seconds.

All DTOs expose public mutable properties and memberwise initializers, conforming to Codable, Sendable, and Equatable:

| Type | Fields |
| --- | --- |
| `CloudOperation` | `operationID: UUID`, `entity: String`, `action: String`, `id: UUID`, `expectedVersion: Int64`, `payload: [String: JSONValue]` |
| `CloudOutcome` | `status: String`, `code: String?`, `record: [String: JSONValue]?`, `revision: Int64?`, `warnings: [String]?` |
| `CloudChange` | `revision: Int64`, `entity: String`, `id: UUID`, `record: [String: JSONValue]` |
| `CloudChangePage` | `changes: [CloudChange]`, `nextRevision: Int64`, `hasMore: Bool` |

`CloudOutcome` initializes optional fields to nil. `JSONValue` is a Codable, Sendable, Equatable enum with `.string(String)`, `.number(Double)`, `.bool(Bool)`, `.null`, `.array([JSONValue])`, `.object([String: JSONValue])`. Keep version/revision cursors as the DTO’s Int64 fields.

## Wire requests

Every request includes `apikey`; authenticated requests also include `Authorization: Bearer <accessToken>`. JSON request keys below are literal:

| Method and route | Body |
| --- | --- |
| POST `/auth/v1/otp` | `{"email":"…","create_user":true}` |
| POST `/auth/v1/verify` | `{"email":"…","token":"…","type":"email"}` |
| POST `/auth/v1/token?grant_type=refresh_token` | `{"refresh_token":"…"}` |
| POST `/auth/v1/logout` | `{}` |
| POST `/functions/v1/delete-account` | `{}` |
| POST `/rest/v1/rpc/apply_operation` | `{"operation":{"operationID":"UUID","entity":"item","action":"upsert","id":"UUID","expectedVersion":0,"payload":{…}}}` |
| POST `/rest/v1/rpc/library_changes` | `{"after_revision":0,"page_size":200}` |

Item payload keys are `title`, `kind`, `url`, `filename`, `contentType`, `byteCount`, `note`, `collectionID`, `createdAt`, `attachmentID`, `storagePath`, `sha256`. Collection payload keys are `name`, `tint`, `createdAt`. Entity is `item`/`collection`; action is `upsert`/`delete`. Reusing an operation UUID requires identical payload and expected version; persist that UUID before the first request. Conflict responses remain `CloudOutcome` values; preserve the returned server record alongside the local edit.

## Immutable originals

Paths must contain exactly three UUID components: `owner/item/attachment`, with owner equal to the authenticated session user. Traversal, encoded separators, empty components, and cross-account paths are rejected before network access. Upload uses POST `/storage/v1/object/originals/<path>` with `x-upsert: false`, original content type, and base64 JSON `x-metadata` containing `sha256`. Imports are limited to 25 MiB. The SHA-256 parameter is a 64-character hex checksum calculated by the app at import.

If create returns HTTP 409, the client performs an authenticated GET of the same private object and accepts success only if the downloaded bytes exactly equal the local original. Exact equality verifies both content and length; a mismatch throws `BackendError.originalMismatch` and never triggers an overwrite. A network/download failure remains an error. Normal original downloads return unmodified bytes.

## Errors and testing

`BackendError` is Equatable and LocalizedError. HTTP 401/403 maps to `.unauthorized`, expired local sessions to `.sessionExpired`, malformed JSON to `.invalidResponse`, other failed HTTP statuses to `.httpStatus(Int)`. Response bodies are excluded from errors. Transport/file-system errors propagate. The caller must refresh expired sessions explicitly and retry durable operations without changing their UUID.

Inject an actor conforming to `HTTPTransport`, whose `send(_ request: URLRequest) async throws -> HTTPResponse` returns `HTTPResponse(data: Data, statusCode: Int)`. This boundary permits real request/body/error tests without network credentials.

Run `swift test --package-path Packages/BookmarkCloud` from the repository root. Portable tests do not prove live backend provisioning, email delivery, Keychain, native UI, or device sync.
