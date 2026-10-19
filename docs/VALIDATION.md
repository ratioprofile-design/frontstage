# Validation

## Automated gates

- Run `swift test`: the suite must execute actual tests, not just build.
- On macOS run `./scripts/build-macos-app.sh`: compile the SwiftUI/AppKit client and verify the development bundle's plist and ad-hoc signature.
- CI runs both gates on macOS. A workflow file alone is not evidence that they passed.

## Required native manual checks

1. Launch the bundle, create two scenes, edit titles, summaries and rich text. Verify scene selection keeps the right content and native text undo/redo works.
2. Save a `.frontstage` file, quit and reopen it through Open or Import. Compare saved text, metadata and unknown fields. Select a save destination explicitly; every import starts a copy.
3. Import a sanitized `.backstage` fixture containing Tamil, formatted dialogue, shots, nested unknown fields and a document. Verify untouched HTML remains unchanged in saved JSON. Edit one scene and inspect AppKit's formatting conversion.
4. Confirm import and editing do not modify the source file. Confirm Save As refuses a `.backstage` destination and an alias pointing to one.
5. Edit a project, then New/Open/Quit. Check Save, Cancel, Discard, cancelled save panels and failed writes do not silently lose current edits.
6. Check large projects, long scripts, keyboard navigation and accessibility. These have not been performance-validated.

There is no claim of full feature parity, macOS runtime validation, cloud synchronization or fresh-machine restoration until the relevant checks execute.

## Screenplay milestone checks

The screenplay milestone contained 16 portable tests. Native tests exercise semantic `sc-*` HTML round trips, nested wrappers, Tamil and emoji, native Return/Tab flow, and untouched-source preservation. PDF tests verify every paragraph is extractable from a long multipage screenplay, page ranges cover all source text exactly once, Letter/A4 page geometry, omitted scenes, orphan-cue movement and destination symlink protection. CI saves test results and generated PDFs in `Frontstage-screenplay-validation`.

The native suite also tests formatting undo and rich clipboard insertion into dialogue. macOS run [39333279146](https://github.com/ratioprofile-design/frontstage/actions/runs/39333279146) passed the full test step, release compilation, bundle signature/plist checks, and both artifact uploads. The log-capture pipeline explicitly enables pipefail so a test or compilation failure fails the job. Run 39333067564 is not valid test evidence: it exposed a missing `try` in a test and the pipeline status bug, both corrected before the passing run.

On a Mac, also review the Write/Pages switch and native Print dialog. Check Option+1–7, Tab/Shift+Tab, text undo, IME composition, scene headings and scene numbers. Compare preview and exported PDF visually. Custom imported font/layout settings are not implemented; MORE/CONT'D was added in phase 4.

## Five-phase expansion

The portable suite now executes 40 tests. Additional coverage includes bounded/coalesced undo, recovery, revision restore and line-diff reconstruction, cycle rejection/diagnosis, stable scene links, casting confirmation and metadata patches, legacy breakdowns, strict dates/times, overnight schedules, workload/turnaround checks, CSV quoting/source protection, and an integrated five-phase save/recover/undo workflow.

Native tests add dirty-state/selection reconciliation, explicit recovery, protection of unreadable recovery data, character-cue discovery, undo of production edits, live call-sheet PDF text, and long-dialogue continuation headers/footers. The validation artifact includes call-sheet-sample.pdf as well as screenplay PDFs.

Phase 7's combined native suite and app packaging passed in run [39336366519](https://github.com/ratioprofile-design/frontstage/actions/runs/39336366519). The final bundling script additionally compiles both arm64 and x86_64 and verifies the universal binary with lipo before signing; this is build evidence for both architectures, not an Intel runtime test.

Manual checks still needed: crash/relaunch recovery in the installed app, board dragging/zoom/selection, role/casting forms, day/date/time controls across user locales, visual typography and the printer dialog. No cloud synchronization, distribution signing/notarization or full Backstage parity is claimed.

## Current cloud run

Swift 6.0.3 on Linux: 11 XCTest tests executed, 11 passed, 0 failures. The trailing Swift Testing message reports zero tests because this suite uses XCTest; it is not the suite result. Bash syntax and plist parsing also passed. The first macOS CI run (91a584b, run 39330601726) succeeded, covering core tests, native compilation and the development bundling script. Interactive UI checks are still outstanding. Follow-up macOS CI run 39330835052 (8741b72) also succeeded: the suite includes three native TextKit/workspace tests, followed by a release app build, plist/signature validation and artifact upload. The development zip is available from that run.
