# Architecture

Universal Bookmarker separates portable domain rules, native persistence, capture handoff, and the account service. It targets iPhone on iOS 17 or newer in Swift 6 mode.

## Native storage

`LibraryStore` is a main-actor observable store consumed by SwiftUI screens. SwiftData persists encoded domain records, pending operations, account cursors, capture deduplication, and local-to-account import mappings. Transactions are explicitly saved.

Originals live in Application Support, separated by scope. Imports copy files before metadata is committed. Failed persistence rolls back the record and removes the new copy. Thumbnail decoding is bounded. Downloaded originals are checked against their recorded SHA-256 checksum.

`BookmarkCore` owns Codable/Sendable values, validation, metadata search, import limits, and capture manifests. `BookmarkCloud` owns authenticated HTTP requests and wire values. Neither package depends on SwiftUI, SwiftData, Keychain, or a provider SDK. The app stores sessions in Keychain.

## Scope and capture

Device saves use the `device` scope; account saves use `account:<user UUID>`. Signing in does not silently upload device saves. Explicit import creates account records while retaining the device source until server acknowledgement.

The Share extension reads a non-secret destination descriptor once before loading providers. It copies provider files while temporary URLs remain valid, then atomically publishes a complete manifest and originals to the scoped App Group inbox. It never opens the main database or reads credentials. The main app ingests matching-scope captures and acknowledges only after its own durable commit. Unpublished staging directories are never ingested.

Extension success means saved on the iPhone. The main app must open to import and sync. App Group entitlements and provider behavior require signed-device testing.

## Sync and backend

Account edits enter a durable outbox before transmission. Retries retain their UUID and exact request. Originals use create-only private paths and upload before metadata. Duplicate uploads require authenticated byte comparison.

The server derives ownership from the token, serializes each account's revisions, validates expected versions, and stores replay receipts. Change pages and local cursors commit together. Tombstones prevent deleted records returning from old devices. Deleting a collection clears membership while preserving items.

Network failures retry with capped backoff. Authentication failures retain changes and request sign-in. Conflicts retain local edits and the latest remote record for user resolution. Metadata deletion queues Storage cleanup through server functions.

Supabase provides email-code Auth, PostgreSQL RPCs and row policies, private Storage, and account functions. [Setup](backend-setup.md) and the [wire contract](backend-contract.md) describe this boundary. Committing source does not provision services.

The existing web prototype is a separate client. Its source, authentication integration, and use of the shared contract remain necessary. This repository does not change the Vercel deployment.
