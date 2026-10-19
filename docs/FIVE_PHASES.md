# Five-phase native development run

The original Backstage checkout remains read-only. All changes belong in frontstage. Each phase is committed, tested and pushed; full parity is not implied by completion of these milestones.

| Phase | Deliverable | State |
| --- | --- | --- |
| 3 | Bounded project undo/redo; debounced local recovery and explicit startup recovery | Passed portable tests and macOS CI run 39334231361 |
| 4 | Named scene revision snapshots; restore/diff; MORE/CONT'D page continuations | Passed portable tests and macOS CI run 39334593999 |
| 5 | Native spatial causality board; move cards; connect scenes; cycle validation | Passed portable tests and macOS CI run 39334843832 |
| 6 | Native character/casting records and scene breakdown editing | Implemented; validation in progress |
| 7 | Shooting-day assignments, call sheets and production exports | Pending |

Phase 3 keeps up to 40 project changes, coalescing a burst of edits to the same field within a second. Project undo uses Command+Option+Z and redo Command+Option+Shift+Z; normal Command+Z remains native text undo. Recovery copies are written after 800 ms without edits to Application Support/Frontstage/Recovery/session.frontstage, never to an imported source. Recovery is not a replacement for saving: the most recent fraction of a second can be lost in a crash. Startup asks whether to recover or discard the copy. Successful saves and explicit discard clear it. Test workspaces use injected stores and do not write to the real user's app directory.

Phase 5 is a spatial story graph. It supports drag, zoom, multiple imported board IDs, connections, cycle diagnosis/prevention, omission and script ordering. Timeline lanes, ripple editing, group editing and a full Excalidraw replacement remain separate work.

Phase 6 keeps role keys stable; whole-role renaming/deletion is not provided. It supports script-cue discovery, scene assignments, character profiles, per-role casting options and confirmation, contact/notes/status edits, and manual production requirements. Unknown metadata remains stored. If both legacy breakdown aliases exist, editing targets breakdownData and preserves breakdown without merging or overwriting it. Advanced auditions, media management and crew/continuity modules remain unported.
