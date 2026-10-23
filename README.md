# Universal Bookmarker

A native iPhone library for links, screenshots, photos, PDFs, and files, designed to share one private library with the web.

![Library, Search, and Save concept](docs/design/ios-concept.png)

## Project status

The visual direction is accepted. The written build specification is ready for review; application implementation has not started.

- [iOS build specification](docs/superpowers/specs/2026-10-23-universal-bookmarker-ios-design.md)
- [Original prototype review](docs/design/prototype-review.md)

The proposed app uses SwiftUI, local persistence, an iOS Share extension, and a Supabase-backed sync service. Search and collections stay close to the library; saving never requires selecting a collection.

The existing web prototype is at <https://universal-bookmark.vercel.app/>. It has no connected backend yet. This repository does not currently change that deployment.

Native compilation and simulator checks will run on macOS with Xcode. Backend setup, Apple signing, and recovery of the approved original logo assets are recorded in the specification.
