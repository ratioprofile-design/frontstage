# Frontstage

A native macOS rewrite of Backstage, built with Swift, SwiftUI and AppKit. The original `ratioprofile-design/Backstage` repository is not modified. There is no React, Tauri, JavaScript runtime or web view in this client.

**Status: native editing, story sequencing and production milestones, not a complete Backstage conversion.** Native editing, recovery, sequencing, discovery and PDF workflows have portable and macOS tests and CI build checks. Interactive app testing and full feature parity are still outstanding; see the validation notes below for recorded runs.

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
- Project undo/redo, plus a separate debounced recovery copy and startup recovery prompt.
- Named scene revisions, text comparison, restore with automatic backup, and printed MORE/CONT'D dialogue continuations.
- Connected story/script workspace: colored lanes, estimated duration, dependency-aware ripple, snapping, groups, milestones, locks, cause/effect inspection and explicit script reordering. See [sequencer behavior and parity coverage](docs/CAUSALITY.md).
- Character profiles and script-cue discovery; per-role casting options, confirmation and contact details; manual scene breakdowns.
- Shooting days, scene assignments and estimates, cast call times, call-sheet PDF/print output, and schedule/breakdown CSV exports.

Save projects explicitly. A separate recovery copy is written after 800 ms without changes; it does not overwrite an imported file or guarantee the latest keystroke survives a crash. Imported projects always open as copies, including `.frontstage` files; select the destination when saving. The app does not access the old app's storage directory automatically. If a recovery copy is unreadable, it is preserved and automatic recovery writes are disabled for that session.

## Write and preview a screenplay

Add a scene, fill in its heading, then write in the editor. Choose an element from the format picker or use Option+1 through Option+7. Tab cycles element types; Shift+Tab cycles backward. Return moves character/parenthetical to dialogue, and dialogue to the next character cue. Return on a blank formatted line returns to action. TextKit retains control of marked text during input-method composition.

Switch **Write → Pages** to preview the entire active screenplay. Choose US Letter or A4 in the toolbar. Use **Export PDF** or **File → Print Screenplay** (Command+P) for output. The paper choice is currently a session setting. The validation artifact includes generated example PDFs for both paper sizes.

The native screenplay layout uses 12-point Courier with a 1.5-inch binding margin and 1-inch other margins. It does not yet reproduce custom Backstage font/layout settings, page locks or dual dialogue. Imported HTML remains untouched until that scene is edited; editing normalizes its HTML and retains screenplay types plus bold/italic/underline, while unsupported inline styles, media and links need fidelity review.

## Other workspaces

Use the View menu in the toolbar to choose **Revisions**, **Board**, **People**, **Breakdown** or **Production**. Write and Board show the sequencer above the selected scene's script; resize the divider or hide either pane. Selecting a beat selects its script immediately. The right dot starts a connection; select the effect beat to complete it. Shift-click selects multiple beats. The inspector shows duration, storyline/sequence names, causes, effects and issues. Revisions and breakdowns operate on the scene selected in the sidebar. People can discover character cues from the screenplay, then you can assign roles in Breakdown. Production assigns active scenes to shooting days; a scene moves from its previous day when assigned to another. Fill in actual location/crew/safety details before exporting or distributing a call sheet.

The Project menu provides undo (Command+Option+Z) and redo (Command+Option+Shift+Z), while Command+Z remains text undo. See the [five-phase run](docs/FIVE_PHASES.md) for each milestone and its limits.

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

The bundling script builds arm64 and x86_64, combines them into a universal Mac executable, verifies both architectures and ad-hoc signs the bundle for development. Native tests execute on the CI runner's architecture; Intel runtime review is still needed. The bundle is not Developer ID signed or notarized. On a Mac, open `Package.swift` in Xcode to build/debug the Swift package. The macOS GitHub Actions workflow builds an app artifact; availability depends on a successful workflow run.

## Portable core tests

`swift test` exercises JSON types, legacy import, Tamil HTML, preservation of unknown fields and large numeric IDs, scene updates, invalid project rejection, ID allocation, credential removal, atomic save/reopen, source file protection and symlink protection. On Linux, the executable only reports that macOS is required; it does not render or validate the UI.

## Migration and future platforms

See [migration plan](docs/MIGRATION.md), [feature status](docs/FEATURES.md), and [validation checklist](docs/VALIDATION.md).

The selected browser direction is a web application with shared projects and sync, like Notion, rather than remote streaming of Mac windows. `FrontstageCore` keeps document operations independent of SwiftUI. Future web and Windows clients should share a versioned service/document contract; they will require separate UI implementations. A local JSON format alone does not implement synchronization.

Do not add private service keys to the source or document schema. Native credentials should use Keychain; shared backend credentials belong on a server. Authentication, collaboration, conflict resolution, hosted storage, AI, Maps and other integrations are not implemented yet.

Development builds are on the [Actions page](https://github.com/ratioprofile-design/frontstage/actions). Choose the latest successful run. Download `Frontstage-macOS-development` while signed into GitHub, unzip it, then unzip the enclosed `Frontstage-macOS.zip` to get `Frontstage.app`. The app requires macOS 14+ and is intended for development testing. `Frontstage-screenplay-validation` contains the test report, sample Letter/A4 screenplays and a sample call-sheet PDF. Per-phase validation links are recorded in [FIVE_PHASES.md](docs/FIVE_PHASES.md).
