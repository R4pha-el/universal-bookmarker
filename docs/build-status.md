# Build and release status

This repository contains a development implementation. Portable tests and source parsing do not establish native compilation or hosted-service behavior.

## Source and verification

Implemented source includes SwiftUI saving/browsing/account flows, SwiftData and original-file persistence, a durable sync outbox, Share capture, portable domain/transport packages, Supabase policies/RPCs/account functions, and generated Xcode targets with CI.

Fresh local checks used Swift 6.0.3 on Linux and Node.js 24:

| Check | Result |
| --- | --- |
| BookmarkCore | 16 tests passed |
| BookmarkCloud | 21 tests passed |
| PostgreSQL and account-handler suite | 14 tests passed |
| Native Swift syntax | 48 files parsed; Apple types are not resolved |
| Project generation, plists, scheme | Deterministic generation and structural checks passed |
| Native Xcode build and simulator tests | First CI build failed; fixes and rerun pending |
| Live Supabase and signed-device Share capture | Not run; configuration required |

Backend tests use PGlite PostgreSQL with Supabase fixtures and mocked service HTTP. They cover replay, conflicts, cursors, ownership, storage probes, original validation, deletion ordering, and a two-owner create collision interleaving. The latter uses a trigger, not multiple concurrent connections.

Independent review prompted fixes for stale edits, conflict refresh, rejected-operation retries, capture/account transitions, pending counts, backoff, native initialization/test isolation, cross-owner collisions, and storage authorization probes.

## Publication and CI

Source was pushed to [GitHub main](https://github.com/R4pha-el/universal-bookmarker) at commit `39c487b`, preserving the existing seed history. The seed-only `test` file was subsequently removed in commit `6303ecdea13a940db9efcba4a9eb4dc3f7f7151e`.

The [first GitHub Actions run](https://github.com/R4pha-el/universal-bookmarker/actions/runs/39993958538) passed both portable Swift package suites but failed overall. Native compilation found an `NSItemProvider.loadItem` return-value mismatch in Share capture. The backend runner used Node.js 22, which does not support the suite's `--test-isolation=none` option; the required runtime is Node.js 24 or newer. Corrections and a fresh workflow result are pending. No native build or simulator test success is claimed.

Clearing the repository's placeholder About description was denied with HTTP 403 because repository-administration permission is unavailable to the connection. The repository owner can clear it in GitHub's About settings.

## Before release

1. Complete the macOS and backend workflow after the current fixes; resolve any remaining native failures.
2. Configure Supabase and validate the [deployment checklist](backend-setup.md).
3. Configure signing and matching App Groups; test Safari, Photos, and Files captures on a device.
4. Validate accessibility, Dynamic Type, reduced motion, appearance, and storage behavior on supported devices.
5. Restore approved dragging-bookmark logo assets and prepare icons, screenshots, privacy disclosures, and release metadata.
6. Obtain the web client's source and integrate the shared API if web and iOS are to ship together.

Publication stores source; it does not provision services, publish an App Store build, or update the existing Vercel deployment.
