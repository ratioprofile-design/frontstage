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

## Current cloud run

Swift 6.0.3 on Linux: 11 XCTest tests executed, 11 passed, 0 failures. The trailing Swift Testing message reports zero tests because this suite uses XCTest; it is not the suite result. Bash syntax and plist parsing also passed. The first macOS CI run (91a584b, run 39330601726) succeeded, covering core tests, native compilation and the development bundling script. Interactive UI checks are still outstanding. Native TextKit/workspace tests were added afterward and require their own CI result.
