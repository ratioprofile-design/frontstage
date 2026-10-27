# Dual dialogue implementation

Updated 27 October 2026.

## Completed: shared document operations

`Sources/FrontstageCore/DualDialogue.swift` and `Server/Public/dual-dialogue.js`
implement lossless pairing/unpairing of two adjacent character/dialogue passages
within one beat. Parentheticals, inline emphasis, Tamil, emoji, comments, and
surrounding paragraphs retain their original HTML. Neither operation changes beat
or scene identity, ordering, board containers, notes, breakdown, or dependencies.

The representation is additive HTML in the existing screenplay field:

```html
<div class="sc-dual">
  <div class="sc-dual-column sc-dual-left">…character and speech…</div>
  <div class="sc-dual-column sc-dual-right">…character and speech…</div>
</div>
```

Cue indices refer to top-level paragraphs, ignoring whitespace/comments and inline
formatting. A column begins with exactly one nonempty character cue, followed by
dialogue/parenthetical paragraphs and at least one nonempty dialogue paragraph.
Cross-heading/action selections, malformed markup, nested legacy paragraph
wrappers, and existing pairs are rejected rather than rewritten. This scanner is
an editing validator, not an HTML sanitizer or a replacement for HTML import.

Project operations validate the target and existing text protection. Swift uses
the existing atomic script-document transaction; JavaScript returns a separate
candidate document for the workspace edit transaction. History and saving remain
owned by the workspace. Shared fixture tests run in both CI workflows; Swift also
covers project history, revision restoration, and metadata preservation.

## Pending before enabling controls or publishing

The current editors, HTML sanitizer, and exporters do **not** yet support this
layout. These APIs are intentionally not connected to user-facing actions. This
branch is a foundation milestone, not a completed or published dual-dialogue
feature. Existing saved projects and released UI remain unchanged.

1. Add Mac attributed-text metadata and TextKit column layout, including codec
   round trips through Write and beat popup editors. Commit whole beat ranges so
   paragraph-by-paragraph serialization cannot flatten pairs.
2. Add browser nested-paragraph editing, allowlisted classes, and column layout.
   Register the module in the offline cache/build hash when it becomes a runtime
   dependency. Preserve the mobile drawer behavior and active editor DOM.
3. Add pair/remove actions to the existing Styling/context menus. Validate selection
   ownership and locks before editing. Define safe Enter, selection deletion, and
   scene-splitting behavior within pairs, with Tamil composition and caret tests.
4. Add browser print pagination, native PDF, and DOCX output. Verify long unequal
   speeches span pages without losing, duplicating, clipping, or interleaving text.
5. Exercise the same fixture in actual Mac and browser editors, reopen/offline
   reload, undo/redo, revisions, and collaboration. Run existing board/timeline/
   popup tests and build the Mac application before release.

Production page freezing and revision marks follow dual-dialogue acceptance;
they remain unimplemented. This milestone does not close broader product gates
in [PHASE_STATUS.md](PHASE_STATUS.md).
