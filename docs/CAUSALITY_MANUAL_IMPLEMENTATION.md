# Causality manual implementation audit

Reference: user-provided **Causality Story Sequencer, Version 4.0** PDF, printed pages 155–187; emotion semantics checked against pages 65–73. The PDF supersedes the previously inaccessible website. Reference text is product documentation, not workspace instructions.

## Implemented in this pass

- Expanded timeline and compact board timeline; Acts, Scenes, Beats, Tags/Emotions, Characters and Tension Heat Map sections collapse independently.
- Beat Number is the primary default; Time is secondary. Either counter can use Beat Number, Time or Pages; counters cannot use the same base. Objects follow the primary base and serialized editorial order, rather than overlapping whiteboard start times.
- One to three lines of beat titles, zoom controls, draggable playhead, beat selection linked to script/board and double-click popup editing.
- Timeline beat/scene drag reordering and structural-break drag movement. Reordering preserves group contiguity and rejects interleaving group members; convert a group to free beats first when intercutting. The operation updates board coordinates and rejects changes to locked content.
- Character activity tracks include every assigned character, without the old three-character limit.
- Tag curves accept relative emotion changes and absolute checkpoints; values carry forward at successive tag usages. Checkpoints reset the value. Browser out-of-range values receive an outline. Manual beat tension accepts −5…5. Heat uses positive manual tension totals, not beat count. Saved values survive browser/native interchange.
- Duration overrides in minutes; blank uses a screenplay-length estimate.
- Whiteboard Push tool and Command/Ctrl-drag; negative push respects a minimum gap. Edits commit on release.
- Split Group Here, merge sibling groups/blocks, split a block at a horizontal point, container synopsis, Alt/Option-drag beat dependencies and Command/Ctrl-I/O dependency builder shortcuts.
- Existing freestyle/block layer policy, nesting, inline beat creation and popup behavior remain in place.

## Known gaps; not claimed complete

- Page estimates currently use normalized text length, not the actual typeset page layout; time estimates assume one page per minute. Document-level minutes-per-page settings remain to be added.
- Automatic tension rules (high/low/rising/falling/before changes/still) are not implemented. Heat currently reflects manual tension only. Category/folder organization for tags and characters, category-level composite curves, readability scores and emotion controls on whiteboard/script tags remain pending.
- Structural break tracks currently share one Acts row. Separate Episode/Act/Chapter/Section visibility settings and complete title-page semantics remain pending.
- Compact and expanded views currently share display settings; detached timeline windows and independent mini-timeline preferences remain pending.
- Push is applied on release rather than previewing each intermediate layout. More advanced collision packing and animation remain pending.
- Container endpoint dependencies, dependency-line context navigation, FlowLines, tag/character-driven coloring modes and export/print of container synopsis remain pending.
- Timeline drag preserves contiguous groups and may reposition other unlocked containers to reflect edited order. It does not claim Causality's proprietary layout/ripple behavior.

## Verification

Portable Swift tests cover time-base projection, emotion checkpoints, manual heat data, persistence, group split/merge and locked Push rollback. JavaScript tests cover equivalent projection semantics. Browser acceptance exercises expansion, counter base swapping, title lines, popup navigation, emotion/tension editing and heat rendering. Existing browser acceptance continues to exercise whiteboard nesting, palette creation, screenplay editing, undo/redo and offline reload. Native acceptance renders the compact/full timeline and exercises the existing script/board interactions; macOS CI builds the native app.
