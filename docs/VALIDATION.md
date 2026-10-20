# Validation record

Updated 20 October 2026. Automated checks establish the behavior they exercise; they do not establish complete Causality parity or installed-product acceptance.

## Current automated evidence

- Local Swift 6.0.3/Linux: **92 XCTest tests pass**, including source protection, atomic persistence, revisions, causal constraints, locks, snippet split/merge/reorder, three-way merges, Office archives, Tamil/layout models and embedded media.
- Whiteboard geometry/index test: 10,000 blocks/beats, 50 visible-range queries, approximately 0.06 seconds in this host's debug run. Deeply nested group bounds are tested. No interactive FPS claim.
- macOS [run 39390067427](https://github.com/ratioprofile-design/frontstage/actions/runs/39390067427) passed native tests, universal release compilation, bundle/plist/signature validation and artifact uploads. It covers TextKit, screenplay/parallel PDFs, DOCX semantics/XLSX cells and popup identity, including the multi-snippet and shared-project UI changes. Later source commits have fresh CI runs; use their actual conclusions.
- Windows [run 39389625081](https://github.com/ratioprofile-design/frontstage/actions/runs/39389625081) passed native release compilation, selected shared-model tests, a native popup edit plus cause/resolve/save/reopen smoke, and development/validation artifact upload. It does not establish clean-machine installation or full Mac parity.
- Browser/server [run 39390067350](https://github.com/ratioprofile-design/frontstage/actions/runs/39390067350) passed API authentication/permissions/version conflicts/retries/restart tests, JavaScript merge fixtures and actual Chromium popup/offline/reconnect editing. The browser smoke also passed locally.
- Container [run 39389625116](https://github.com/ratioprofile-design/frontstage/actions/runs/39389625116) built the source Docker image and checked the nonroot runtime health. Local Docker builds were blocked by apt-mirror DNS in this environment; successful CI is the container evidence.

Mac run 39389625132 exposed an old test expectation that adding a scene switched to Write. The implementation now intentionally defaults to Whiteboard; the test expectation was updated. Failed runs are not preview evidence. The final status links below should be checked for the newest source revision.

## Artifacts and commands

[Swift workflow](https://github.com/ratioprofile-design/frontstage/actions/workflows/swift.yml): `Frontstage-macOS-development` contains the nested development app zip; `Frontstage-screenplay-validation` contains test XML/logs, native workspace/popup captures, sample PDFs and synthetic projects. A grouped whiteboard → popup edit → split → undo/redo → save/reopen → PDF acceptance test also generates artifacts.

[Browser workflow](https://github.com/ratioprofile-design/frontstage/actions/workflows/server.yml): `Frontstage-browser-validation` contains `browser-whiteboard.png`, `browser-popup.png` and the browser log.

[Windows workflow](https://github.com/ratioprofile-design/frontstage/actions/workflows/windows.yml): development executable/runtime zip and validation logs with the synthetic saved project.

```sh
swift test
# On macOS:
./scripts/build-macos-app.sh
# After building Server:
python3 Server/Tests/smoke.py
node Server/Tests/merge.mjs
node Server/Tests/browser-smoke.mjs
```

The browser smoke needs Playwright/Chromium as described in [Server README](../Server/README.md). Linux builds neither display nor validate AppKit; native checks run on macOS CI.

## Required hands-on acceptance

1. Launch the installed app on Apple Silicon and Intel. Compare full-window layouts to both supplied screenshots and the popup to an actual open-editor reference.
2. Exercise selection, multi-block/layer dragging, nested groups, multi-snippet movement, pan/zoom/fit, context actions and locked/cyclic failures at several zoom levels.
3. Test native focus, keyboard formatting, Tamil IME composition, popup dismissal, text/project undo and multiple editor isolation.
4. Import representative sanitized legacy projects with Unicode, formatting, metadata and media. Split/reorder/merge, save/reopen and inspect source preservation.
5. Compare screenplay, two-column, call-sheet and Office exports visually; test the native printer dialog and custom fonts.
6. Interrupt the app and relaunch recovery; cancel unsaved replacement/save panels and simulate failed writes.
7. Use Mac/browser accounts with owner/editor/reader access on two devices; test offline edits, conflicts, permissions removal and reconnect.
8. Measure interactive performance and accessibility with large real projects. Validate Windows runtime dependencies and installation on a clean machine.

Developer ID signing/notarization, actual public hosting, complete Windows/browser feature parity and all phase acceptance gates remain unverified. See [release](RELEASE.md) and [roadmap](ROADMAP.md).
