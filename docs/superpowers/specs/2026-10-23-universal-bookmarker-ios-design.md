# Universal Bookmarker: iOS app and shared-library contract

Date: 2026-10-23
Status: implementation authorised by the user; source implemented, native and live-service validation tracked in [build status](../../build-status.md)

## What this version will do

Open an iPhone app and immediately see saved links, screenshots, photos, PDFs, and files. Save from inside the app or another app's Share menu. Find items by title, website, filename, or an optional note. Collections help when wanted; they never block saving.

The first build includes the native app, Share extension, backend migrations and access policies, a documented sync API, and macOS build checks. A configured backend lets compatible clients use the same account and library. Connecting the existing Vercel prototype requires its source and is a separate client integration; this work will not claim that deployment already syncs.

## Confirmed brief and design decisions

- User requirement: links plus screenshots, photos, PDFs, and files.
- User requirement: one library across iOS and web.
- Main problem: saves are scattered across apps; retrieval and manual organisation also cause friction.
- Existing project: a web prototype, with no backend; its UI is to be improved.
- Accepted direction: Library first, prominent Search, optional Collections, and an Add action.
- Accepted visual concept: [Library, Search, and Save](../../design/ios-concept.png), using sample content.
- First-release assumption: a private personal library, without collaborative or public collections.
- First-release platform choice: native SwiftUI for iPhone, minimum iOS 17. Use system components so appearance follows the installed OS. iPad optimisation follows this iPhone release.
- Product naming: Universal Bookmarker, preserving the approved dragging-bookmark identity.

## Why this approach

Library first makes scattered saves visible immediately. A search-first home is less useful before a library grows; a board-first home makes mixed documents and links harder to scan. The chosen layout keeps browsing useful and makes global search one tap away.

Use a managed Supabase backend because web and iOS both need access to the same private records and files. CloudKit would require a separate web identity/integration strategy; a custom hosted API adds service operations before the saving workflow is established. These architectural choices are implemented in source; the services still require provisioning.

## Screens and navigation

The tab bar has Library, Collections, and Search, in that order. Tabs navigate. Add is a toolbar action; it is not a tab. Account and sync status are accessible from the profile button.

### Library

Open into a newest-first list grouped by local calendar day. Filters are All, Links, Photos, and Files. Screenshots belong to Photos; PDFs belong to Files and retain a visible PDF type label. Rows show a useful thumbnail or compact type icon, title, and relevant source/type metadata. A missing image never reserves a large blank region.

Tapping a row opens its preview. A context menu exposes Rename, Move to collection, Share, and Delete. Deletion requires confirmation. Empty state: "Your library starts here" with an Add button. Loading and offline states preserve already-saved content.

### Search

One search destination searches the whole local library across title, URL/host, original filename, and optional note. Matching is case- and diacritic-insensitive. Results use the same rows as Library and display their scope and result count. Empty input invites a search; no-result copy offers clearing the query or filters.

Search does not promise image recognition, OCR, semantic AI, web-page-body indexing, or PDF-body indexing in this release. Downloaded metadata remains searchable offline.

### Collections

Create, rename, and delete private collections. An item can belong to one collection or none. Deleting a collection leaves its items in Library. Collection detail reuses library rows and type filters. Saving defaults to no collection.

### Add and import

A cancellable sheet titled "Add to library" offers Add a link, Choose photos, and Choose files. Dismiss the chooser before presenting a system picker. Photo import covers screenshots; file import covers PDFs and other documents.

For links, enter a valid HTTP or HTTPS URL. Fetch title and preview opportunistically after durable save; a preview failure does not fail the save. The URL/host supplies a fallback title. Repeat submissions of one capture cannot create duplicate items. A separately saved identical URL prompts Open existing or Save again.

Import originals into app-managed storage before reporting success. Keep the original filename and media type. Allow up to 20 selections per import and 25 MiB per file in this initial release; validate limits in both the client and backend. Report individual failures without discarding successful selections. Photos receive an editable default title; no automatic content description is promised.

### Item preview

Links use an in-app Safari presentation with an Open in browser action. Photos support a native image preview. PDFs and supported files use Quick Look. Unsupported formats retain their metadata, original download, and system Share action. Detail offers editing title and an optional note, moving to a collection, and deletion.

Originals imported on this phone remain available offline. Files saved on another client download on demand and are cached after viewing; metadata can be visible before an original downloads. The interface distinguishes a network failure from an unsupported file.

### Account and sync

Saving locally works before sign-in. The profile view offers "Connect sync" and shows whether the library is On this iPhone, Waiting to sync, Syncing, Synced, or Needs attention. These states reflect completed work, not merely connectivity.

Use email one-time-code sign-in for the first version, with code entry, resend cooldown, expiry/error feedback, and session refresh. Store session credentials in Keychain. Configure the provider's email template to send a code rather than its default magic link. No social sign-in provider or password-reset flow is required for this release.

After sign-in, show the connected account's library. Ask before importing existing device-only items into the displayed account. If declined, retain the device-only library behind an "On this iPhone" library switch in the profile view. If accepted, stage account copies with stable migration mappings so retries cannot duplicate them; keep each device-only original and source record until its account upload is acknowledged, then remove the source record and show the acknowledged account item. A failed migration preserves the source and a visible retry action. Captures arriving for the device-only scope after the migration snapshot remain in that scope until separately imported.

Local and account libraries are isolated; signing into a different account cannot upload another account's pending saves. Signing out with pending work requires syncing it or explicitly discarding that local work. Count published Share captures as pending work. Clear that account's cached data only after this choice. Account deletion is an authenticated, confirmed server action that removes account records and stored originals; it is part of the release requirements.

## Share extension and offline capture

The Share extension accepts web URLs, supported images, PDFs, and file attachments using the same size/type rules. Copy input into an App Group staging directory and atomically publish a capture manifest only after its files are complete. Include a capture UUID and destination library scope. Read a non-secret shared descriptor containing the stable scope identifier and a generation at capture start; permanently retain that destination in the manifest. Account switches publish a new descriptor atomically. A late capture for a prior account is quarantined until that account is authenticated again or the user explicitly discards it; it is never reassigned to the next account or silently removed during sign-out cleanup. The extension never writes the main app's SwiftData store and never reads authentication secrets.

Report "Saved on this iPhone. Open Universal Bookmarker to sync." only after the manifest is durable. Do not imply an upload completed. If App Groups are unavailable, report an actionable error rather than accepting a save that will be lost.

On launch and foreground entry, the main app imports complete manifests for the matching library scope. Import is idempotent by capture UUID. Retain the manifest until metadata and original files are durably ingested. Incomplete copies remain outside the import queue. Handle extension termination and repeated delivery without duplicate bookmarks or partial records.

The main app drains the upload queue when foregrounded and when the user retries. Background execution may improve timeliness but is never required for correctness. A Share capture reaches another device after the main app runs and sync succeeds; instant extension-to-web delivery is outside this first version.

## Architecture and responsibility boundaries

| Unit | Responsibility | Boundary |
| --- | --- | --- |
| SwiftUI features | Library, Search, Collections, capture sheets, previews, account state | Consume domain operations and observable state |
| Library repository | Local metadata, filtering, durable mutations and upload outbox | SwiftData stays inside the main app |
| Original-file store | Atomic copies, scoped file paths, original downloads and cache | Referenced by item UUID; no file bytes in metadata records |
| Capture inbox | App Group manifests and import deduplication | Shared serialization contract, no database/session sharing |
| Sync coordinator | Uploads, retries, change application and conflicts | Calls backend transport through an interface |
| Auth session | OTP exchange, Keychain credentials and refresh | Authenticated API requests; no secrets in app resources |
| Backend | Account ownership, metadata, revision checks and private object storage | SQL migrations, documented RPC contract and access policies |

Use Foundation URLSession for the small HTTP transport and system frameworks for the interface, persistence, photo selection and previews. Do not add third-party iOS packages merely for scaffolding. Configuration supplies the backend URL and client publishable key; server service-role credentials are never shipped to clients or committed.

## Data and sync contract

An item has a client-generated UUID, owner/library scope, kind (link, photo, PDF, or file), title, optional source URL, optional original filename/media type/byte count, optional note, optional collection UUID, creation/update dates, server version, deletion marker, and local sync status. Attachment identity and storage path are immutable. Collections have their own UUID, owner, name, version, and deletion marker.

Save local metadata, original files, and an outbox operation durably before showing success. Each operation has a stable UUID. Retry an identical request with the same UUID; changing its payload or expected version requires a new operation UUID. Photo/file objects upload to deterministic owner/item/attachment paths using create-only writes; storage policies deny overwrites. If an upload retry finds an existing object, verify its byte count and SHA-256 against the imported original before accepting it as success. A mismatch is an actionable error, never an overwrite. Replacing an original requires a new attachment UUID. Publish remote item metadata only after its required original exists. Link previews are optional and do not block publication.

Backend mutation operations validate ownership and expected record version, apply the mutation, record the idempotency result, and append a change atomically. Serialise mutation revisions per user using a transaction-held counter lock; cursor order must follow committed mutations. A client requests paginated changes after its durable cursor and advances that cursor only after applying a complete batch locally.

A stale version returns a conflict, not silent overwrite. Preserve both the server value and pending local edit; offer Keep this device's edit or Use synced version. A new intentional overwrite uses a new operation UUID and the latest server version. A server deletion is authoritative for that UUID; offer saving a retained local edit as a new item instead of recreating a deleted record.

Deleting a collection atomically clears item memberships, increments affected item versions, and publishes those changes with the collection tombstone. Reject cross-owner collection references. When an otherwise valid offline edit references a collection that was deleted, preserve the item edit with a nil collection and explain that the collection was removed; a stale item version still follows the normal conflict flow. No mutation may restore membership in a tombstoned collection.

Deleting items creates tombstones so offline devices cannot resurrect them. Exclude tombstones from search and normal browsing. Remove associated private originals through an authenticated cleanup operation; failed cleanup is retried and never leaves a publicly accessible file. Keep logical tombstones for the lifetime of the account in this first version.

Retry transport failures with capped exponential backoff and expose a manual Retry action. Handle authentication expiry separately from network errors. No metadata or original is labelled Synced until required server writes are acknowledged.

## Privacy and backend setup

All user records require row-level ownership policies. Use a private storage bucket with policies binding object paths to the authenticated account. Signed URLs, if used for preview, are short-lived and are not persisted as public item URLs. Reject unsupported remote mutations and cross-account references. The app executes no imported file content and performs no server-side arbitrary-URL crawler in this release.

Provide migrations, example non-secret configuration, email-code template instructions, storage limits, account-deletion handling, and setup documentation in the repository. Provisioning a Supabase project and email delivery requires the user's service account/configuration. No existing backend credentials are available in this workspace. Unconfigured builds remain explicitly device-only; they cannot claim cross-device sync.

## Visual identity and accessibility

Follow the accepted light mockup's information hierarchy with semantic system colours and system text styles. Respect the device's dark appearance, Dynamic Type, VoiceOver, Reduce Motion and Reduce Transparency. Preserve readable metadata, labelled icon controls, growing rows, safe areas, and comfortable default 44-point control targets. Do not encode sync or selection state solely with colour.

Use the approved monochrome mark: a clothed man facing left and dragging the outlined bookmark behind him to the right with a taut rope. The original approved logo kit is not present in this fresh workspace and must be recovered before final branded app assets are produced. Do not replace it with a newly generated mark. Keep branding primarily in the app icon and appropriate account/empty views; saved content drives the main interface.

The concept image establishes visual direction. It does not establish measured contrast, working accessibility, real system component behavior, or a functioning application.

## Acceptance and verification

1. Save a link, screenshot, photo, PDF, and generic file; force-quit and reopen; originals and metadata remain available.
2. Import from the Share extension; terminate/relaunch at import boundaries; one durable capture produces one item and no partial original.
3. Search titles, hosts, filenames, and notes across all types, including case/diacritic differences; absent queries show a useful no-result state.
4. Collections are optional; rename/move/delete operations preserve items and appear consistently in Library and Search.
5. With a configured backend and the same account on two test clients, verify create, original download, edit conflict, offline retry, deletion and no resurrection. A separate web test client can validate the API until prototype source is supplied.
6. Verify a second account cannot read or mutate the first account's metadata, originals, or collection references. Verify sign-out/account switch cannot transfer pending captures.
7. Verify invalid URLs, oversized files, interrupted uploads, expired sessions, unavailable previews and unknown file formats produce actionable states without losing completed saves.
8. Verify Dynamic Type, VoiceOver order/labels, light/dark appearances, reduced motion and navigation on supported iPhone sizes using Xcode and a simulator/device.
9. Run macOS CI for compilation, domain/persistence/sync tests and focused UI smoke checks. Confirm App Group entitlements and the Share extension on a signed device before distribution.

This Linux workspace has no Swift compiler, Xcode or simulator. Source review or configuration validation here cannot substitute for a native build. GitHub macOS CI and a signing-capable Mac/device provide those checks. GitHub storage does not constitute an App Store/TestFlight release.

## Delivery boundaries

This specification covers the native iPhone app and its backend contract/configuration. It excludes collaborative libraries, AI/OCR, full offline web-page archives, browser extensions, subscriptions and an iPad-specific redesign. Integrating/redesigning the current Vercel web client follows once its source is supplied. Publishing to TestFlight/App Store requires the user's Apple developer team, signing and release review.

The repository will be private at `R4pha-el/universal-bookmarker`, as requested. Store the specification and mockup there first; implementation follows the required written-spec and implementation-plan reviews.

## Reference sources

- [Supabase email OTP](https://supabase.com/docs/guides/auth/auth-email-passwordless): code-based email sign-in and required template configuration.
- [Supabase row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security): ownership enforcement for exposed data.
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control): private object policies.
- [Apple App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups): shared container for the app and extension.
- The requested Apple design/HIG review informed navigation, search, sheets and list hierarchy. The repository contains our design decisions; it does not redistribute the third-party skill's Apple reference text.
