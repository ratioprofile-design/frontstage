# Validation record

Updated 21 October 2026. Automated checks establish the behavior they exercise; they do not establish complete Causality parity or installed-product acceptance.

## Current automated evidence

- Local Swift 6.0.3/Linux: **105 XCTest tests pass**. New coverage includes rigid group boundary moves, nested ungrouping, protected deletion, causal compaction and lock rollback, marker edits, snippet-aware concurrent merges, structural merge conflicts, and interleaved script ranges/numbering/source retention.
- Whiteboard geometry/index test: 10,000 blocks/beats, 50 visible-range queries, approximately 0.06 seconds in this host's debug run. Deeply nested group bounds are tested. No interactive FPS claim.
- macOS [run 39558537080](https://github.com/ratioprofile-design/frontstage/actions/runs/39558537080) passed native tests, universal release compilation, bundle/plist/signature validation and artifacts. It includes act markers/group undo, popup identity, keyboard/accessibility, actual block-edge dragging, and PDF/DOCX extraction checks proving interleaved scene ranges appear in order exactly once. Sample interleaved PDF/DOCX files are included in validation artifacts.
- Windows [run 39558537115](https://github.com/ratioprofile-design/frontstage/actions/runs/39558537115) passed native compilation, selected shared-model tests including new whiteboard/document-merge/script-sequence suites, popup/cause/save/reopen smoke, and artifacts. It does not establish clean-machine installation or full Mac parity.
- Browser/server [run 39558537110](https://github.com/ratioprofile-design/frontstage/actions/runs/39558537110) passed API authorization/origin/retry/restart tests, generic/snippet merge fixtures, and actual Chromium concurrent same-scene edits/offline merge, group/ungroup/delete/undo/redo, markers, compaction and popup dragging in same-origin and static cross-origin modes. Cold local offline reload/reopen also passes locally; subsequent CI runs cover the service-worker addition.
- Container [run 39558537085](https://github.com/ratioprofile-design/frontstage/actions/runs/39558537085) built the source image and checked the nonroot service. Local Docker builds were previously blocked by apt-mirror DNS; successful CI is the container evidence.
- Vercel [deployment check 39557903141](https://github.com/ratioprofile-design/frontstage/actions/runs/39557903141) verified the current browser HTML/JS/CSS and board operations module. Later checks verify their own source revisions and offline shell. Static delivery does not establish a hosted shared backend.

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
