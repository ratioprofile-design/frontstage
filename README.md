# Frontstage

A native macOS rewrite of Backstage, built with Swift, SwiftUI and AppKit. The original `ratioprofile-design/Backstage` repository is not modified. There is no React, Tauri, JavaScript runtime or web view in this client.

**Status: first native foundation, not a complete Backstage conversion.** The portable model and persistence pass 11 tests, and the initial macOS CI build and app bundling passed. Interactive app testing and full feature parity are still outstanding; see the validation notes below.

## Current scope

- Native project/scene navigation; scene title and summary editing.
- AppKit rich-text scene editing, using TextKit and its native undo support.
- New projects and import of existing `.backstage`/JSON project copies.
- Versioned `.frontstage` saves with atomic writes. Import source paths are never used as default save destinations; saving to `.backstage` is rejected.
- Preservation of unported project and scene fields, including nested data. Untouched scene HTML is retained; editing a scene converts its HTML through AppKit and may normalize unsupported formatting.
- Known legacy credential fields are removed on import/save. This is not a general secret detector: inspect legacy project data before sharing it.
- Unsaved-change prompts when replacing a project or quitting.

There is no autosave or recovery journal yet. Save explicitly. Imported projects always open as copies, including `.frontstage` files; select the destination when saving. The app does not access the old app's storage directory automatically.

## Run on a Mac

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+ or appropriate command line tools).

```sh
swift test
swift run Frontstage
```

For an app bundle:

```sh
./scripts/build-macos-app.sh
open build/Frontstage.app
```

The bundle is ad-hoc signed for development. It is not Developer ID signed or notarized. On a Mac, open `Package.swift` in Xcode to build/debug the Swift package. The macOS GitHub Actions workflow builds an app artifact; availability depends on a successful workflow run.

## Portable core tests

`swift test` exercises JSON types, legacy import, Tamil HTML, preservation of unknown fields and large numeric IDs, scene updates, invalid project rejection, ID allocation, credential removal, atomic save/reopen, source file protection and symlink protection. On Linux, the executable only reports that macOS is required; it does not render or validate the UI.

## Migration and future platforms

See [migration plan](docs/MIGRATION.md), [feature status](docs/FEATURES.md), and [validation checklist](docs/VALIDATION.md).

The selected browser direction is a web application with shared projects and sync, like Notion, rather than remote streaming of Mac windows. `FrontstageCore` keeps document operations independent of SwiftUI. Future web and Windows clients should share a versioned service/document contract; they will require separate UI implementations. A local JSON format alone does not implement synchronization.

Do not add private service keys to the source or document schema. Native credentials should use Keychain; shared backend credentials belong on a server. Authentication, collaboration, conflict resolution, hosted storage, AI, Maps and other integrations are not implemented yet.
