# Native Share Extension

`ShareViewController` is a public `UIViewController` hosting a native SwiftUI review form. The extension target's principal class is `$(PRODUCT_MODULE_NAME).ShareViewController`; link the local `BookmarkCore` package and use iOS 17 / Swift 6.

## Integration

- Set `INFOPLIST_FILE` to `ios/ShareExtension/Info.plist` and `APPLICATION_EXTENSION_API_ONLY` to `YES`.
- Set `APP_GROUP_IDENTIFIER` identically on the app and extension, and grant that group in both targets' signing entitlements. `AppGroupIdentifier` is expanded into the extension's Info.plist. No fallback directory is used.
- The main app must write its initial destination with `CaptureInbox(rootURL: groupURL.appendingPathComponent("CaptureInbox")).writeDestination(...)` before the first Share capture. It publishes a fresh descriptor atomically on library/account changes.
- Compile the four top-level Swift source files in the extension. Exclude `Tests/` from the extension source build phase. The native test target can compile `CaptureStaging.swift` alongside `Tests/CaptureStagingTests.swift`, requiring only Foundation/XCTest.
- Embed the extension in the main app with the normal Xcode app-extension build phase.

## Save lifecycle

The extension snapshots the non-secret destination descriptor before loading any item provider. That snapshot remains fixed across loading, review and save retries. It does not read credentials or open SwiftData. Missing App Group access or an unreadable destination produces an error directing the user to open the main app.

Provider file representations are copied synchronously while the callback's temporary URL is valid. File URL inputs are copied while their security scope is open; image providers that only offer data use a bounded post-load size check. Originals are streamed into `CaptureStaging/<capture UUID>/` with a 25 MiB limit and complete-until-first-authentication file protection. Up to 20 readable files plus one HTTP(S) link can form a capture. Individual failures remain visible on the review form; successful inputs can still be saved. Unknown regular-file formats remain files; folders are rejected.

`CaptureInbox.publish` receives only completed staged originals. Its atomic manifest publication is the commit point. Until it succeeds, the extension never shows success or calls `completeRequest`. A successful save displays exactly: “Saved on this iPhone. Open Universal Bookmarker to sync.” Done then completes the extension request. Cancel removes unpublished staging and cancels the request; it is disabled during the short publication transaction. The main app owns ingestion, account quarantine, sync and acknowledgement.

Interrupted extension processes may leave unpublished `CaptureStaging` directories. These directories are never an inbox and must never be ingested. The app may remove old unpublished staging directories during maintenance, but must not remove `CaptureInbox` entries for a different account.

## Verification

The staging tests cover byte preservation after provider-file deletion, size-limit rejection with no partial original, directory rejection and overwrite prevention. No Swift compiler or Xcode was initially available in this Linux environment, so a native build/test run remains required. On a signing-capable device, test Safari, Photos, Files (including iCloud-downloaded inputs), cancellation, App Group misconfiguration, oversized imports, account switching while the share sheet is open and process termination before/after publication. Verify that an old-account manifest never appears under a newly selected account.
