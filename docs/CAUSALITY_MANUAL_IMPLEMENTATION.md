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

- Page estimates still use normalized text length rather than the actual typeset page layout. Time estimates now use the saved document-level minutes-per-page setting.
- Automatic tension rules (high/low/rising/falling/before changes/still) are not implemented. Heat currently reflects manual tension only. Tag category and character group assignment/collapse are now available in both timelines. Research-linked nested folder ordering, category-level composite curves, readability scores and emotion controls on whiteboard/script tags remain pending.
- Episode/Act/Chapter/Section tracks now have independent visibility and intervals; complete episode title-page semantics remain pending.
- Compact and expanded timelines now retain independent local display preferences. Detached timeline windows now hide the mini-timeline until docked.
- Push is applied on release rather than previewing each intermediate layout. More advanced collision packing and animation remain pending.
- Container endpoint dependencies, dependency-line context navigation, FlowLines, tag/character-driven coloring modes and export/print of container synopsis remain pending.
- Timeline drag preserves contiguous groups and may reposition other unlocked containers to reflect edited order. It does not claim Causality's proprietary layout/ripple behavior.

## Verification

Portable Swift tests cover time-base projection, emotion checkpoints, manual heat data, persistence, group split/merge and locked Push rollback. JavaScript tests cover equivalent projection semantics. Browser acceptance exercises expansion, counter base swapping, title lines, popup navigation, emotion/tension editing and heat rendering. Existing browser acceptance continues to exercise whiteboard nesting, palette creation, screenplay editing, undo/redo and offline reload. Native acceptance renders the compact/full timeline and exercises the existing script/board interactions; macOS CI builds the native app.

## Follow-up: independent structure and display settings

- Episode, Act, Chapter and Section tracks are calculated independently, with custom/legacy markers retained in Acts. A boundary in one track does not truncate another. Marker type can be chosen at creation or changed afterward; moves retain it.
- Tracks menu controls visibility independently from section collapse. Mini and expanded timelines keep separate time bases, zoom, title lines, collapsed sections and hidden tracks in local preferences. The compact view initially hides analytical tracks. Preferences do not modify shared project content.
- Timing settings save minutes per page (0.1–10) in the project. Explicit beat duration overrides are unchanged. The script-length estimate remains approximate.
- Regression coverage includes crossing structure boundaries, project round-trip, invalid timing rollback, preference serialization, full/compact restoration, browser break creation and exported timing values.

## Follow-up: board and timeline zoom

- Both workspaces expose minus, percentage/reset and plus controls on Mac and browser. Clicking the percentage resets to 100%.
- Browser whiteboard zoom scales its content and scroll bounds together. Placement, inline entry, group nesting, dependency picking and Push convert pointer coordinates into board coordinates. Fit frames the selected beats, or all containers when nothing is selected.
- Browser Command/Ctrl-wheel zooms around the pointer; Command/Ctrl +/−/0 works with board/timeline focus. Mac supports trackpad magnification; its existing whiteboard Command-scroll gesture remains available.
- Timeline zoom-out now continues below the previous minimum without jumping inward after Fit. Browser zoom preserves the viewed position.
- Browser regression coverage exercises nesting and inline beat creation while zoomed, card scaling, reset and timeline zoom-out below the previous lower bound. Native build/interaction validation is a separate macOS CI gate.


## PDF timeline follow-up (24 October 2026)

Re-read printed pages 180–187, with tag category defaults on page 53 and character organization on page 146.

- Right-click either counter to select Beat Number, Time or Pages. Primary and secondary remain distinct.
- Right-click track headers to choose visible structure levels; the Beats header additionally offers title line counts and color strength. Color strength is also directly adjustable and persists separately for mini/full timelines.
- Tag tracks now belong to named categories (General by default). Each category separates emotions from ordinary tags. Character tracks belong to named groups (Main Characters by default). Right-click a member track to assign its category/group. Groups collapse independently; membership is saved in the project and survives Mac/browser interchange.
- A separate timeline window is available on both platforms. The mini-timeline is hidden while detached; docking restores it. The detached view uses full timeline preferences and shares selection/project edits with the main workspace.
- Browser wheel and Up/Down arrows zoom the timeline; Shift-wheel remains available for scrolling. Native Up/Down zoom and trackpad magnification are supported. Native labels remain pinned when scrolling horizontally.

### Remaining limits against the reference

This is **not complete Causality equivalence**. Nested research folder ordering is not yet mirrored; groups currently sort by name. The PDF mentions a readability score without specifying its calculation, so no invented score is presented as equivalent. Page timing still uses text-length estimation rather than typeset pagination. Automatic tension policies/composites and episode title pages remain open. Native plain-wheel zoom, the script workspace mini-timeline, and exact typography/layout matching also need further work. Existing contiguous-group restrictions on timeline reordering remain.

### Evidence

Browser acceptance covers context counter changes, category assignment/collapse, color strength, detached-window zoom/docking, and the prior editing/drag/offline paths. Core tests cover serialized group assignment, default categories, invalid edits and backward-compatible preferences. Native acceptance opens/closes the detached window and renders the full timeline; macOS CI is required for AppKit/SwiftUI verification.
