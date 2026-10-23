# Shared library API contract

Routes are relative to the Supabase project URL and use HTTPS. Send the client publishable key in `apikey`. Authenticated routes also require `Authorization: Bearer <access token>`. JSON keys below are literal. Ownership comes from the token, never a submitted owner ID.

## Auth and account routes

| POST route | JSON body |
| --- | --- |
| `/auth/v1/otp` | `{"email":"you@example.com","create_user":true}` |
| `/auth/v1/verify` | `{"email":"you@example.com","token":"123456","type":"email"}` |
| `/auth/v1/token?grant_type=refresh_token` | `{"refresh_token":"…"}` |
| `/auth/v1/logout` | `{}` |
| `/functions/v1/cleanup-originals` | `{}` |
| `/functions/v1/delete-account` | `{}` |

Auth returns Supabase's snake-case `access_token`, `refresh_token`, `expires_at` or `expires_in`, and `user.id`/`user.email`. Store secrets securely and refresh expired sessions before retrying.

Cleanup returns `{"removed":0}` and handles at most 100 queued originals per call. Deletion returns `{"deleted":true}` after freezing writes, removing originals, and deleting the Auth user. Functions independently verify the bearer token; they return 401 for invalid callers, 405 for unsupported methods, 503 for missing server configuration, or 502 with `account_action_incomplete` when an operation must be retried. No caller-supplied account identifier is used.

## Mutation RPC

POST `/rest/v1/rpc/apply_operation`:

```json
{
  "operation": {
    "operationID": "11111111-1111-4111-8111-111111111111",
    "entity": "item",
    "action": "upsert",
    "id": "22222222-2222-4222-8222-222222222222",
    "expectedVersion": 0,
    "payload": {
      "title": "Useful reference",
      "kind": "link",
      "url": "https://example.com/reference",
      "note": "Read later",
      "collectionID": null,
      "createdAt": "2026-10-22T12:00:00.000Z"
    }
  }
}
```

`entity` is `item` or `collection`; `action` is `upsert` or `delete`. Creation uses version 0. Updates/deletion use the latest server version. Deletes require no payload fields. Persist operation UUIDs and exact requests before transmission, retaining both across transport retries. Reusing a UUID with a different request returns `idempotency_mismatch`.

Item payloads contain `title`, `kind`, `url`, `filename`, `contentType`, `byteCount`, `note`, `collectionID`, `createdAt`, `attachmentID`, `storagePath`, and `sha256`, as applicable. Kinds are `link`, `photo`, `pdf`, and `file`. Titles allow 1–500 characters, notes up to 10,000. Links require HTTP(S) URLs and must not carry attachment identity/path/hash/byte count. Non-links require a filename (1–255), content type (1–150), size (0–26,214,400), attachment UUID, exact owner/item/attachment path, and lowercase 64-character hex checksum. Their original must already exist with matching finalized size/checksum metadata. Original identity, path, checksum, and byte count are immutable after attachment.

Collection payloads contain `name` (1–120 characters), optional `tint` (up to 40, default `blue`), and optional `createdAt`. Dates use ISO 8601. A missing creation date defaults to server time.

Outcomes:

- `{"status":"applied","entity":"item","id":"…","record":{…},"revision":1,"warnings":[]}`
- `{"status":"conflict","code":"version_conflict","record":{…}}`, or code `deleted` for a tombstone.
- `{"status":"rejected","code":"…"}`.

Rejection codes include `invalid_operation`, `invalid_payload`, `id_unavailable`, `not_found`, `collection_unavailable`, `immutable_original`, `original_missing`, `idempotency_mismatch`, and `account_deleting`. HTTP success alone does not mean applied. Preserve local edits when resolving conflicts. Tombstoned UUIDs cannot be resurrected; saving a chosen local copy requires a new UUID.

Deleting a collection clears membership and emits updated items before its tombstone. Assigning to an owned deleted collection clears membership with warning `collection_removed`; foreign or missing collections are rejected.

## Records and change pages

Item records contain `id`, `ownerID`, `title`, `kind`, `url`, `filename`, `contentType`, `byteCount`, `note`, `collectionID`, `attachmentID`, `storagePath`, `sha256`, `version`, `createdAt`, `updatedAt`, and `deletedAt`. Collection records contain `id`, `ownerID`, `name`, `tint`, `version`, and those date fields. Nullable fields are JSON null. Accept ISO 8601 dates with or without fractional seconds. Version and revision fields are 64-bit integers.

POST `/rest/v1/rpc/library_changes` with `{"after_revision":0,"page_size":200}`. Page size is 1–200 and the cursor nonnegative. Response:

```json
{
  "changes": [{"revision":1,"entity":"item","id":"…","record":{}}],
  "nextRevision":1,
  "hasMore":false
}
```

Apply complete records including tombstones and commit the cursor with successful local application. Continue while `hasMore` is true. An empty page retains the requested cursor. Revisions are serialized per account under a lock held through mutation commit. Keep account cursors and outboxes separate.

## Private originals

The private `originals` bucket uses `<owner UUID>/<item UUID>/<attachment UUID>` keys with canonical lowercase UUIDs. Upload with POST `/storage/v1/object/originals/<path>`, original bytes, correct `Content-Type`, `x-upsert: false`, and `x-metadata` containing base64 JSON `{"sha256":"<checksum>"}`. Download with authenticated GET of the same path.

Clients can create/read only their own originals; there is no client update/delete policy. Reconcile HTTP 409 uploads through authenticated comparison with the local original; never overwrite. The Swift client accepts a duplicate only when bytes exactly match. Item deletion queues cleanup through the server Storage API.

See the [BookmarkCloud implementation](../Packages/BookmarkCloud/README.md), [deployment setup](backend-setup.md), and [verification boundary](build-status.md).
