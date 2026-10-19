# Frontstage

A native macOS rewrite of Backstage, built with Swift, SwiftUI and AppKit. The original `ratioprofile-design/Backstage` repository is not modified. There is no React, Tauri, JavaScript runtime or web view in this client.

**Status: native screenplay milestone, not a complete Backstage conversion.** The portable model passes 16 tests. The screenplay editor, pagination and PDF output have dedicated macOS tests and CI build checks. Interactive app testing and full feature parity are still outstanding; see the validation notes below for recorded runs.

## Current scope

- Native project/scene navigation; scene title and summary editing.
- AppKit rich-text scene editing, using TextKit and its native undo support.
- Screenplay elements: action, character, dialogue, parenthetical, transition, shot and lyrics. Backstage's `sc-*` paragraph types survive native import/edit/save.
- Editable scene headings and optional scene-number overrides.
- Letter/A4 page preview, PDF export and native printing, using a shared PDF renderer. Disabled scenes are omitted. Page breaks avoid orphaned headings, character cues and parentheticals where the chain fits on a page.
- New projects and import of existing `.backstage`/JSON project copies.
- Versioned `.frontstage` saves with atomic writes. Import source paths are never used as default save destinations; saving to `.backstage` is rejected.
- Preservation of unported project and scene fields, including nested data. Untouched scene HTML is retained; editing a scene converts its HTML through AppKit and may normalize unsupported formatting.
- Known legacy credential fields are removed on import/save. This is not a general secret detector: inspect legacy project data before sharing it.
- Unsaved-change prompts when replacing a project or quitting.

There is no autosave or recovery journal yet. Save explicitly. Imported projects always open as copies, including `.frontstage` files; select the destination when saving. The app does not access the old app's storage directory automatically.

## Write and preview a screenplay

Add a scene, fill in its heading, then write in the editor. Choose an element from the format picker or use Option+1 through Option+7. Tab cycles element types; Shift+Tab cycles backward. Return moves character/parenthetical to dialogue, and dialogue to the next character cue. Return on a blank formatted line returns to action. TextKit retains control of marked text during input-method composition.

Switch **Write → Pages** to preview the entire active screenplay. Choose US Letter or A4 in the toolbar. Use **Export PDF** or **File → Print Screenplay** (Command+P) for output. The paper choice is currently a session setting. The validation artifact includes generated example PDFs for both paper sizes.

The native screenplay layout uses 12-point Courier with a 1.5-inch binding margin and 1-inch other margins. It does not yet reproduce custom Backstage font/layout settings, page locks, dual dialogue or automatic MORE/CONT'D markers. Imported HTML remains untouched until that scene is edited; editing normalizes its HTML and retains screenplay types plus bold/italic/underline, while unsupported inline styles, media and links need fidelity review.

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

Validated development artifact: [macOS CI run 39330835052](https://github.com/ratioprofile-design/frontstage/actions/runs/39330835052). Download and unzip `Frontstage-macOS-development` while signed into GitHub. The included app requires macOS 14+ and is intended for development testing.
