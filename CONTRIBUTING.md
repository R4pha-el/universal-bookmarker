# Contributing

Keep changes focused and describe the user-visible problem before implementation details. For substantial work, discuss the intended behavior in an issue or pull request before expanding the product scope.

## Development

Use Swift 6, iOS 17-compatible APIs, and Node.js 24 or newer for backend tests. See the [README](README.md) for setup and check commands. Keep backend and signing settings in the ignored `ios/Configuration/Secrets.xcconfig`. Use disposable accounts and sample files for testing.

The Xcode project is generated. Change `scripts/generate_project.py`, regenerate, and commit both the generator and resulting project when its structure changes. Do not edit generated project identifiers by hand.

## Before opening a pull request

- Run affected portable Swift and backend suites and record their actual results.
- Regenerate the project and verify that a second generation leaves it unchanged.
- For app or extension changes, run the macOS build and native tests. State when those checks are unavailable.
- Add regression coverage for data loss, scope isolation, idempotency, persistence, and access-control fixes.
- Update documentation when configuration or API behavior changes.
- Run `git diff --check`; exclude credentials, personal saves, caches, and build products.

Keep domain and transport packages independent of SwiftUI and SwiftData. Captures retain the destination selected when capture started; account changes must never reassign queued saves. Report save success only after local durable commit. Preserve operation IDs and exact request bodies across transport retries.

Preserve Dynamic Type, accessible labels, system navigation, and reduced-motion support when changing the interface.
