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
| Native Xcode build and simulator tests | Not run; macOS workflow pending |
| Live Supabase and signed-device Share capture | Not run; configuration required |

Backend tests use PGlite PostgreSQL with Supabase fixtures and mocked service HTTP. They cover replay, conflicts, cursors, ownership, storage probes, original validation, deletion ordering, and a two-owner create collision interleaving. The latter uses a trigger, not multiple concurrent connections.

Independent review prompted fixes for stale edits, conflict refresh, rejected-operation retries, capture/account transitions, pending counts, backoff, native initialization/test isolation, cross-owner collisions, and storage authorization probes.

## Publication blocker

Source is committed locally, preserving the existing remote seed history. Upload has not succeeded: `git push` returned HTTP 403 **Permission denied**, and the connected GitHub API's blob creation returned **Resource not accessible by integration**. The GitHub connection needs write access to repository contents before source and workflow files can be published. No GitHub Actions run is claimed.

## Before release

1. Publish after repository write access is enabled; complete the macOS workflow and resolve any native failures.
2. Configure Supabase and validate the [deployment checklist](backend-setup.md).
3. Configure signing and matching App Groups; test Safari, Photos, and Files captures on a device.
4. Validate accessibility, Dynamic Type, reduced motion, appearance, and storage behavior on supported devices.
5. Restore approved dragging-bookmark logo assets and prepare icons, screenshots, privacy disclosures, and release metadata.
6. Obtain the web client's source and integrate the shared API if web and iOS are to ship together.

Publication stores source; it does not provision services, publish an App Store build, or update the existing Vercel deployment.
