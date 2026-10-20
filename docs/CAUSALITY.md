# Whiteboard and story engine

The native workspace is now a gray, board-dominant surface with compact colored snippets stacked in translucent blocks, named horizontal layers, nested groups, causal curves and a compact timeline. The toolbar toggles script, timeline and properties. The older dark lane sequencer remains as a portable legacy engine; it is no longer the default workspace.

## Editing

Double-click a beat or select it and press Return to open the native floating editor. It edits that stable beat ID even when board selection changes. Done/Escape closes the panel while retaining edits. Title, synopsis, formatted snippet text, characters, tags, story/subtext type and Must Be Caused all persist. Split at Cursor creates linked snippets and rewires outgoing causes.

Shift-click/marquee selects multiple snippets. Drag selected snippets into another block to reorder them while preserving scene ownership. Drag block title/background to move blocks and nested descendants; shift-select blocks to group them. The inspector edits names, layer and width. Block context actions collapse and lock. Use Option/Space-drag to pan, pinch/Command-scroll to zoom around the cursor, and Fit for selection or the whole board. Freehand annotations are project data.

Drag a block's right edge to resize it; inherited block/group/layer locks protect this action. Arrow keys navigate visible beats spatially, and Return opens their popup. Visible beats also expose labels and an Edit Beat action to macOS accessibility. These automated paths still need hands-on assistive-technology review.

Beat context actions include edit, jump to snippet, research, create cause/dependency, must-cause, split, insert before/after, omission and delete. Characters and tags are editable in the popup/inspector. This is not yet exact context-menu parity.

## Causal behavior

- A causal edge requires the effect start to be at least the cause start plus duration. A reference edge is nonconstraining and may run backward.
- Create Dependency From selects a source; click the effect to finish. Reference-only conversion and reasons are available in properties.
- Must Be Caused diagnoses beats with no active incoming cause. Omitted and unused-layer beats do not satisfy this requirement.
- Kahn topological ordering rejects causal cycles. Resolve Causes propagates earliest required starts through converging edges; locked beats/blocks/layers block a required move atomically.
- Ripple is enabled by default for block drags. Horizontal movement changes story starts at 120 board points per estimated page and pushes downstream blocks when required. Turning it off allows free spatial arrangement independently of story time.
- Apply Story Order explicitly orders snippet text and scenes by timeline starts. Spatial movement and script order are separate operations.
- Missing causes and invalid time order appear as issues/badges. Imported cycles can be diagnosed; adding a new causal cycle is rejected.

This is a deterministic forward constraint engine. Backward compaction, tension/readability scoring and undocumented Hollywood Camera Work rules are not claimed.

## Persistence and text

The additive `frontstageWhiteboard` schema separates beat UUIDs, numeric scene IDs, blocks, nested groups, layers, dependencies, annotations and viewport. Viewing a legacy project creates a read-only projection; saving an edit preserves unknown fields. Native snippets own HTML; active snippets assemble the parent scene's script exactly once. Split/reorder/merge, scene roles and revision restore retain snippet identity/boundaries where supported.

Whole-scene script replacement is rejected when multiple linked snippets exist, protecting their ranges. Moving between blocks retains scene ownership. Unused/omitted text remains in the whiteboard and is excluded from printed script. Script text locks prevent inclusion/text changes that would alter locked scene content.

Portable tests cover cycles, locks, atomic failures, grouping, split/merge, unknown fields, source protection, ripple and script ordering. Geometry uses a spatial index and viewport culling, with a 10,000-beat regression. That is not an interactive frame-rate benchmark.

See [validation](VALIDATION.md) for automated evidence and [phase gates](ROADMAP.md) for unverified reference behavior. The two supplied screenshots guide layout; neither shows the open popup editor.
