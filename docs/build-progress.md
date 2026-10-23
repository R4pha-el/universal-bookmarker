# Implementation ledger

Plan: `docs/superpowers/plans/2026-10-22-ios-app.md`

## Decisions

- User's "now you can build" authorises implementation from the written specification with the subsequently supplied visual references. Continue without further design approval prompts.
- Work on a feature branch in this new dedicated project directory. No existing product code or user changes are present; avoid another worktree and preserve the documentation commit.
- Keep platform floor at iOS 17, using Swift 6 mode and available system APIs. The external SwiftUI skill's newer platform defaults do not replace the agreed target.
- Native compile/device validation requires macOS; do not label parser checks as a native build.

## Interface checks

| Tasks | Shared boundary | Decision |
| --- | --- | --- |
| 1 / 3 / 4 / 5 | BookmarkCore value types and capture JSON | Public Sendable/Codable domain values; no SwiftData in the extension |
| 2 / 4 | Auth, mutation/changes RPC and private objects | Backend agent documents wire JSON; app adapter follows it |
| 3 / 4 | LibraryStore | Main-actor observable store; UI owns views only |
| 1 / 5 | Package and app targets | Local Swift package, iOS 17, Swift 6 |

## Progress

- Baseline: clean documentation-only repository, commit fb2c0bf; no pre-existing product tests.
- GitHub: requested repository returns 404 to the connection; createRepository previously denied by integration.
