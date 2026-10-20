# Story sequencer

The requested reference is Hollywood Camera Work's **Causality Story Sequencer**, confirmed by the user. This implementation brings its general linked story/script workflow into Frontstage. It is not a verified pixel-identical or feature-complete reproduction. The user has now supplied two reference screenshots: these define the target whiteboard layout. The whiteboard has maximum priority, and a Causality-style popup editor is required. See [the remaining roadmap](ROADMAP.md) for phases 8–19 and acceptance gates. The current lane-based split view is an intermediate implementation. Reference-site requests returned HTTP 403; the current implementation's algorithm reference was the original Backstage lane/ripple engine, read without modifying that checkout.

## Available workflow

Write and Board show a dark, horizontal story sequencer above a native screenplay editor. Beat selection and text updates share the same project. Resize the divider, or hide either pane. The board uses colored compact beats, storyline bands, a story-page ruler, curved causal links and vertical milestone markers.

- Add a beat with a lane's **+** or **Story → Add Beat**. Add more storylines from Story. Rename a storyline in the beat inspector; its context menu changes color, collapse state and lock state.
- Drag a beat horizontally or into another lane. Shift-click selects multiple beats. Preview ripple changes during the gesture; release records one project undo step. A failed gesture leaves the project unchanged.
- **Ripple** preserves the existing order of beats in each lane and pushes effects after their causes, using beat duration and a 24-point gap. A move toward an earlier predecessor stops at that predecessor. Ripple is forward collision resolution; it does not automatically pull every later beat left when a gap opens.
- **Snap** chooses nearby grid positions, neighboring starts/ends and milestones, excluding the moving selection. Grid spacing is one quarter of an estimated story page.
- The right dot starts a connection; click its effect beat or left dot to finish. The inspector selects **Cause → effect** versus a nonconstraining **Reference**, records the reason and removes links. Cyclic causal links are rejected. References may run backward without changing causal order.
- The inspector edits estimated duration from 0.5 to 20 pages. Duration changes ripple through lane neighbors and causes/effects. These estimates are independent of actual PDF pagination.
- **Story → Group Selected Beats** groups unlocked beats in one lane. Select a sequence with a beat's context menu, then drag the selection together. Rename the sequence in the inspector. Ungroup removes membership without changing text. Sequence bounds follow member movement.
- Add an arbitrary named milestone at an estimated page via Story. Remove a marker with its context menu. Milestones are visual guides and snapping targets, not automatic act rules.
- **Resolve Flow** solves all lane/causal constraints on the current board. **Compact Lane** removes unnecessary gaps before solving. Locked beats and lanes stop a conflicting ripple rather than moving silently.
- Turning Ripple off permits manual crossing/reordering. Invalid cause order and lane overlaps are shown as story issues and red links. When imported connections oppose lane order, use Ripple off to place the effect later, or remove the conflicting link, then resolve again.
- Moving cards leaves screenplay order alone. **Apply Board Order to Screenplay** explicitly sorts that board's editorial slots by story position, preserving other boards' slots. It participates in project undo.
- Omit/include and delete are available on beat context menus. Deletion removes that beat's links and can be undone. Existing production-day references are preserved and become stale-assignment warnings until reassigned.

## Engine and persistence

The portable Swift engine constructs one directed graph from causal edges and consecutive beats in each lane. Kahn topological traversal propagates earliest valid starts through converging causes and lane collisions. A combined causal/lane cycle, a blocked locked beat or out-of-range coordinates fails atomically. No recursion is used for sequencing, and a 1,000-beat chain is covered by a regression test.

Legacy `x`, `w`, `trackIndex`, `startTime`, `durationPages`, `durationWidth`, `causalityLanes`, `causalityGroups`, `groupId` and `sectionBreaks` are read where available. Edited coordinates use 120 document points per estimated page; widths, timeline estimates and group bounds are kept consistent on sequencing edits. Native lock flags and connection kind are additive `frontstageLocked`/`frontstageKind` fields. Unknown beat, lane, connection and group fields remain intact. Merely viewing the sequencer does not rewrite the project. Legacy lane/group data stored only in browser localStorage is not automatically discoverable in a project file.

Text is still modeled as one script scene per beat. Project undo/recovery includes the full board and text state. Shared projects, network collaboration, web and Windows clients remain separate future work.

## Parity still requiring work or reference review

| Area | Coverage |
| --- | --- |
| Linked sequencer/script panes | Implemented with native SwiftUI/AppKit; interactive macOS review required |
| Dependencies, lane ripple, snapping, durations and locks | Implemented Swift constraint engine; portable regression tests |
| Groups, milestones and cause/effect inspector | Implemented basic same-lane sequences and visual markers |
| Whiteboard layout, compact stacked beats and popup editor | User reference screenshots received; board redesign and popup implementation pending, prioritized in ROADMAP.md |
| Exact fonts, colors, spacing, window/panel arrangement and gestures | Visual/interaction comparison pending; supplied second image shows a context menu, not an open text editor |
| Arbitrary nested beats/groups and independent script ranges per beat | Not implemented; one scene per beat |
| Semantic story conditions, alternative outcomes, character knowledge/state rules | Not implemented; the engine validates explicit ordering, not screenplay meaning |
| Automatic bidirectional compaction, advanced conflict suggestions | Not implemented; forward ripple plus explicit lane compaction |
| Native Causality document import/export | Not implemented; supports Backstage/Frontstage JSON |
| Reference product keyboard shortcuts and all editing commands | Not verified; Frontstage shortcuts remain available |
| Large-board viewport culling, marquee selection, performance parity | Not implemented or benchmarked; no FPS claim |

The macOS validation artifact includes a synthetic `.frontstage` story and a native workspace PNG generated by the hosting-view integration test, in addition to the existing PDFs and reports. This validates native construction and shared editor content; it does not replace hands-on drag, resize, focus, keyboard and visual comparison checks.
