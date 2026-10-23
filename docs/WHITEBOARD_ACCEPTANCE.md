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

### Application script sidebar and beat drops

The application sidebar now contains the top-aligned script reader across workspaces instead of the scene-title list. Display supports expanded/collapsed beats, index cards, content-only and final-script reading, character/tag/synopsis and container details, margins, zoom, search/filter and presets. Following board selection is optional so independent reading does not jump. The sidebar uses a larger reading font without altering document typography or exports. Episode organization and production-location overlays are not included in these controls.

Slugline fields offer typing completions without adjacent arrow menus. Character, transition, parenthetical and shot paragraphs suggest matching entries while typing; accept with Enter/Tab and dismiss with Escape. Custom values and IME composition remain supported.

Dropping onto another beat creates or joins a beat group. Moving loose beats or detaching group members does not create visible blocks; empty loose-beat and automatic group containers are cleaned up. Explicitly created blocks are retained, including empty ones.

### Creation palette and layer block policy

Lane, Block, Group and Beat tools can be dragged onto the whiteboard in Mac and browser. A dropped lane is inserted after the destination lane; a block or group starts empty. Beats placed on flat layers remain loose. Use **Layer Settings → Use Blocks** on Mac (also available in a lane's context menu), or the lane's **Blocks: Off/On** button in the browser. Enable blocks before creating a block, then drop beats/groups inside it. Model validation rejects loose creation or movement into block-enabled layers and blocks on explicitly flat layers, including non-drag commands and import.

Policy changes are atomic. Enabling blocks on a layer with loose content, or disabling them while blocks remain, is rejected without rearranging existing content. Create an empty lane, enable blocks, create a block manually, and move existing beats into it. Older projects with no policy retain their existing structure; they must explicitly enable blocks before creating new ones with the palette.

Reference access: on 23 October 2026 the supplied manual host returned HTTP 403 from this execution environment. The explicitly described creation and layer rules above are implemented; exact manual-specific beat creation, structural-break semantics and timeline behavior remain unverified/pending readable manual content:
- https://caudocs.hollywoodcamerawork.com/whiteboard/whiteboard-overview.html
- https://caudocs.hollywoodcamerawork.com/beats/creating-beats.html
- https://caudocs.hollywoodcamerawork.com/structural-breaks/structural-breaks-overview.html
- https://caudocs.hollywoodcamerawork.com/timeline/timeline-overview.html

### Existing groups, context actions and compact windows

Dragging an existing group by its title onto an ordinary block now reparents it, including across layers. All descendants adopt the destination layer; moving the destination block carries the group. Locked destinations and cycles are rejected atomically. Browser acceptance covers nesting, export, undo/redo and right-click menus; core tests cover nesting, save/reopen and subsequent block movement.

Browser right-click menus expose beat editing, script navigation, grouping, dependencies, container rename/ungroup/delete, creation and lane policy. Arrow keys and Escape navigate/dismiss the menu.

The Mac board reserves bottom space for its horizontally scrollable creation/action toolbar. The script sidebar defaults narrower and its top controls scroll horizontally in compact windows. Empty screenplay sections show a writing cue, and absent character/tag metadata no longer creates an empty strip. Native acceptance captures a 1073 × 800 window and checks that the board remains within the workspace.

### Inline beat creation and popup focus

Double-click empty board space (or empty space inside a block/group) to enter a beat name on the board. Enter commits a nonempty name and starts another draft below it; Escape cancels the current draft without adding an empty beat. Clicking away commits a nonempty draft. Layer and container locks and block-only rules still apply. Double-clicking an existing beat opens its popup: unnamed/Untitled Beat entries focus Beat Name, named entries focus the screenplay editor. Escape closes the active popup. Browser interaction checks cover consecutive commits, cancellation and both focus paths; Mac acceptance covers inline commit/cancel, named-popup focus and Escape.

### PDF-based timeline and whiteboard pass

The uploaded Causality 4.0 PDF is now the reference for printed pages 155–187. See [the implementation audit](CAUSALITY_MANUAL_IMPLEMENTATION.md) for implemented behavior, regression coverage and the remaining gaps. The earlier website-access limitation no longer prevents reading the reference. This pass does not claim complete manual parity.
