# BookmarkCore

Foundation-only Swift 6 domain values, link validation, local metadata search,
import limits, and an App Group capture inbox. Supports iOS 17 and macOS 14.

`LibraryScope.device.id` is `device`; authenticated scopes use
`LibraryScope.account(userID:)`. Persist scope identifiers and never infer a
capture destination from the account authenticated when it is imported.

## Capture handoff

The app creates `CaptureInbox(rootURL:)` with its App Group's `CaptureInbox`
directory and calls `writeDestination(_:)` whenever the selected scope changes.
The descriptor contains no session secrets. The Share extension reads
`readDestination()` once before awaiting input providers and retains that value.

Build `CaptureManifest(destination:title:url:note:collectionID:attachments:)`.
For originals, provide `CaptureAttachment` values and a `[String: URL]` map from
each attachment's `localFileName` to its provider's temporary file. Names are flat
relative filenames; directory separators, traversal, and symlinks are rejected.
Keep provider files available until `publish(_:files:)` returns.

`publish` validates the entire capture, copies and synchronizes originals inside
a hidden staging directory, writes and synchronizes its ISO 8601 JSON manifest,
and renames the complete directory into the visible scoped queue. Failed or
cancelled work does not enter that queue. A successful repeat of the same UUID
and exact encoded manifest is a no-op; a different payload is rejected. Published
captures use separate directories so the extension and app can operate without
sharing a database. Incomplete staging directories are excluded from `pending`.

The app calls `pending(scopeID:)`, obtains originals with
`fileURL(for:in:)`, commits its own original copies and database transaction, and
only then calls `acknowledge(_:)`. Acknowledgement is safe to repeat. The app must
retain a durable capture UUID deduplication record because the extension may
redeliver a capture after acknowledgement. Other scopes remain queued until the
matching account is available or the user explicitly discards them.

`destinationDescriptor()` and `setDestinationDescriptor(_:)` are convenience
aliases; the first returns `nil` when no descriptor has been written.

Imports allow 20 attachments and 25 MiB per original. This package does not
coordinate authentication, remote uploads, the app database, or account cleanup.
Callers must enforce App Group availability and preserve pending captures during
sign-out. Atomic rename/file synchronization provide the local handoff; signed
device testing is still required to verify entitlements and provider lifetimes.

Run `swift test --package-path Packages/BookmarkCore` from the repository root.
