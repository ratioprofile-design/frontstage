# Write workspace panels

Frontstage’s Write page has scene navigation on the left, a continuous screenplay editor in the center, and a scene inspector on the right. This implementation lives in Frontstage; Backstage is unchanged.

The navigation button toggles scene cards in Write. Writing options contains Display, Styling, Filter, Presets and Options; the element toolbar, zoom, paper theme and inspector toggle remain visible. A4 is the initial paper choice. White, Warm, Dark and Red themes are device-local reading preferences and do not change printed/exported ink or paper. Page-boundary marks are reading guides, not frozen production pagination.

Selecting a card places the caret in its screenplay and highlights that beat without saving highlight attributes into the project. The inspector uses the selected beat’s title, including in legacy projects. The paper context menu can split screenplay text at the caret into a new scene/beat; undo restores the original scene and text. Scene notes and production records remain on the original scene.

The Both notes scope displays Scene and Project notes together in independently scrollable sections. Each section has its own Add Note action and captures its owner when editing. Colors show named swatches (Yellow, Blue, Green, Pink and White); choosing a color preserves note content and formatting.

## Navigation

- Scenes shows one card per whiteboard beat, using Frontstage’s existing dark card styling. The header contains the scene number and beat name; there is no nested beat list or slugline header.
- Double-click a title or synopsis to edit. Enter commits titles; Cmd/Ctrl+Enter commits multiline summaries; Escape cancels. Long summaries offer Show more.
- Locations groups trimmed, case-insensitive location names. Search covers scene numbers, headings, beat titles and synopses.
- New and converted projects use one beat per scene, synchronizing beat titles/synopses with scene titles/summaries. Legacy projects remain usable; Review Converted Copy previews a separate project and metadata allocation without replacing the original.
- Drag before or after a card to reorder using the validated ordering engine. Locked or structurally invalid moves are rejected.
- Hidden script targets offer **Reset filters and reveal**. Navigation does not silently change filters.

## Inspector

**Notes** has Scene and Project scopes. Notes use live Markdown formatting (including `**bold**`, `*italic*`, headings, lists, and code), with no source-view toggle. Note colors, ordering, and deletion remain available. Scene IDs are captured by each editing operation. Merely scrolling does not change the inspector target. Imported scratchpad/audio content is preserved; unsupported notes remain read-only.

**Breakdown** edits the same records as the Breakdown workspace and reports. The 15 standard categories appear with counts; unmatched imported categories appear separately. Select screenplay text and choose **Add Selected Script Text** to retain its quote as the item source. Moving categories preserves extra fields on the original item.

**History** lists scene snapshots newest-first, with summary and screenplay comparison. Restoration creates a backup and leaves notes and breakdown records intact. Locked beats, missing containers, and legacy snapshots without boundaries in multi-beat scenes cannot be restored unsafely.

## Screenplay and beat inclusion

Write opens in Final Script on each entry. Final Script and Content Only use one continuous editing surface with an element toolbar. Scene headings are edited directly in the paper. Character names are discovered from screenplay cues as well as explicitly assigned characters. Panel edits do not replace the active editor during Tamil composition. Story-review and index-card display modes remain available separately.

New scene headings split the current beat at the insertion point and preserve the preceding text. Cross-paragraph changes are committed together. Rejected changes return to the saved document; deleting a whole visible scene moves its beats to Research rather than destroying their records.

- **Active:** participates in the screenplay and page export.
- **Omitted:** stays at the same board position in neutral gray, retaining its original color. It is excluded from the active continuous screenplay. Display → Show Omitted Preview provides a separate read-only preview and an Include Beat action.
- **Pulled out:** removed from the active board and screenplay, retained in Research → Pulled Out. Restore returns the original beat, omission state, metadata and available dependency links. If its original container is missing, select an unlocked destination. Empty implicit containers do not appear as new blocks.

Scene notes, breakdown records, versions and media remain attached to their original scene. Pull Out Scene archives all of that scene’s beats, including repeated appearances. Snapshot restoration cannot duplicate a beat still in Research; restore that beat first. Unused lanes retain their existing separate behavior.

## Layout and persistence

The initial panel widths are 280 and 320 points/pixels. Drag the separators to resize; browser separators also support arrow keys. Panel buttons collapse or reopen them. Below 1180 the right side becomes a drawer; below 900 both sides use drawers with only one open at a time. Widths, visibility, and selected tabs are device-local preferences.

Panel mutations use the existing project history, saving and synchronization paths. The project format remains version 1. Panel changes retain the active screenplay editor. AI breakdown generation and voice recording are not included.

## Verification

Shared fixture: `Tests/Fixtures/write-panels.frontstage`.

- `Server/Tests/write-panel-model.mjs`: projections, summary isolation, legacy/unsupported notes, all categories, movement, concurrent note/summary merge, and unsafe restoration.
- `Server/Tests/write-panels-browser.mjs`: actual panels, scene targeting, Tamil composition, retained editor nodes, resizing/drawers, notes, category movement, snapshot backup, undo/redo, export preservation and cold offline reload.
- `Tests/FrontstageCoreTests/WritePanelTests.swift`: matching native model operations, import preservation, round trips, repeated scenes, locks, unsafe restoration and synchronization merge.
- `Tests/FrontstageAppTests/WritePanelAcceptanceTests.swift`: native workspace hosting, stable screenplay controllers, captured scene targets, undo/redo and resizing.
- Existing workspace parity, whiteboard deletion, script filtering, popup caret, and static browser synchronization suites remain part of regression validation.

Mac UI and AppKit tests run in the Swift macOS workflow; Linux model tests alone do not verify the native UI.

The inclusion checks are in `ScriptInclusionTests.swift`, `Server/Tests/script-inclusion.mjs`, and `Server/Tests/continuous-inclusion-browser.mjs`. They cover archive restoration, missing destinations, revision collisions, inline headings, multi-scene insertion, rejected edits, and whole-scene removal. Native Write acceptance also checks live Markdown and inline heading persistence.
