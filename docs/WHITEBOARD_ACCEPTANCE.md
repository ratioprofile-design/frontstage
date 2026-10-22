# Whiteboard and editor acceptance

The whiteboard is the first release milestone; popup editing is second. Automated tests below do not replace hands-on Mac acceptance or prove exact Causality parity.

## Automated regression checks

- Create independent standalone beats; save/reopen without changing scene identity or text.
- Keep two paper editors open, edit different snippets, close one, and retain the other.
- Browser project undo/redo retains surviving editors, their positions and refreshed content.
- Route Mac screenplay format commands only to the focused screenplay text view.
- Drag selected standalone beats together, snap consistently, preserve spacing at board boundaries, and reject locked or stacked selections atomically.
- Exercise actual native mouse events for a short multi-beat drag and restore positions with project undo; Escape cancels an in-progress drag without committing it.
- Exercise browser drag events with the original grab offset and multiple selected beats.
- Retain existing grouping, cause/effect, import, export, offline and concurrent-edit tests.

## Hands-on Mac checks still required

Record OS version, screen size, processor and build commit with each result.

1. Open three beat editors. Switch between them and the main screenplay, use format shortcuts, undo/redo, close the active editor and reopen it. Confirm each command affects the intended text.
2. Type Tamil and English, use an IME, paste formatted text, select across paragraphs and split at the caret. Confirm source text is preserved once in the linked script and PDF.
3. Drag loose beats, stacks and nested groups within and across layers. Check snapping, locks, boundary clamping, causal ripple and undo. Test mixed selections and cancelled gestures.
4. Test trackpad/mouse pan and zoom, multi-display window placement, small-screen paper scrolling and keyboard-only operation. Check VoiceOver labels and focus order.
5. Open a representative large project and measure interactive dragging, zooming and accessibility response. Geometry benchmarks alone do not establish interactive performance.
6. Save, force-quit, relaunch and recover a working copy. Reopen imports and compare exported screenplay text and ordering.

## Reference-dependent work

Compare the board against the supplied Causality layouts. The supplied open-editor, side-script and hierarchy screenshots now guide the layout. Behavioral examples remain necessary to assess snapping/ripple rules and readability/tension tracks. Until then these are functional Frontstage implementations, not verified exact matches.

## Beat hierarchy and script paper (22 October 2026)

The model distinguishes loose beats, explicit beat groups (`containerKind: beatGroup`), and enclosing blocks. Select beats and use **+ Beat Group**, then **Wrap Selection in Block** to place the group inside a block. Blocks can also contain beats directly. Existing nested containers remain readable. Unwrapping a beat group retains its beats, scene identities, narrative order and cause links.

Cards now grow with their title text and wrap long titles to the container width; drawing, links and hit testing use the same dimensions. **Enter with the whiteboard focused** inserts a beat after the selected beat, retaining its scene and group. Enter inside an editor continues to edit screenplay text.

The optional side script is continuous white screenplay paper with scene headings and semantic dialogue/character indentation. Its text remains linked to the board and popup editors. The browser acceptance capture `browser-hierarchy-side-paper.png` shows the three levels and the paper together. Portable tests verify hierarchy save/reopen and preserved links; native tests exercise board Enter and undo.

### Lane movement and script selection — 22 October 2026

- Drag a grouped beat onto an empty unlocked lane to detach it as a loose beat. Its scene, text and causal links survive; undo restores the group.
- Selecting a beat marks its screenplay passage in the side paper and scrolls it into view.
- Board moves apply left-to-right narrative order, with top-to-bottom lane/card order for horizontal ties. Automatic script scene numbers follow first appearance, top to bottom; explicit scene numbers and continuation identities remain intact.
- Portable model tests and Chromium parity coverage exercise lane transfer, locks, order, highlight and undo. Native acceptance coverage also drives an actual canvas drag.

### Sluglines and screenplay dropdowns

Popup editors, Write and the board-side script expose scene-owned INT./EXT., location and time-of-day controls. Dropdowns suggest standard prefixes/times and existing locations while allowing custom text. Each popup binds to its own scene, including when several popups are open. Locked scripts disable heading changes.

Character, transition, parenthetical and shot choices insert formatted paragraphs without replacing surrounding action/dialogue. Element selection still offers action, character, dialogue, parenthetical, transition, shot and lyrics. Side-paper tools follow the active beat. Browser parity tests cover simultaneous popup heading isolation and formatted insertion; native editor tests cover insertion between existing paragraphs and read-only behavior.

### Close-out audit

The browser now exposes a Ripple toggle. Dragging blocks or loose beats can move into an unlocked destination lane; selected loose beats preserve their relative positions and container IDs across lanes. Forward ripple respects inherited locks and rejects a blocked move atomically. Compaction remains a separate explicit action. The five workstreams and outstanding release/feature gates are tracked in [PHASE_STATUS.md](PHASE_STATUS.md).

### Screenshot reference implementation

The Mac and browser popup use a two-column metadata area, visibility selector, character/tag chips, collapsible Script section, scene-version controls, location dropdowns and screenplay paper. Multiple beat editors remain independent. Versions currently restore the entire linked scene, with a safety revision; they are not independent beat-only versions.

The board-side script now separates scene sluglines (number on the right), collapsible tinted beat headers, metadata and white screenplay passages. Heading editing is in the popup and Write workspace. Groups and blocks support freely positioned beats as well as stacked beats; local offsets persist through save/reopen and ungrouping preserves their canvas positions.

Automated checks cover model persistence, hierarchy, scene order, browser editing and locks. Screenshot captures support visual review; exact Causality interaction equivalence and hands-on Mac acceptance remain open.
