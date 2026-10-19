# Five-phase native development run

The original Backstage checkout remains read-only. All changes belong in frontstage. Each phase is committed, tested and pushed; full parity is not implied by completion of these milestones.

| Phase | Deliverable | State |
| --- | --- | --- |
| 3 | Bounded project undo/redo; debounced local recovery and explicit startup recovery | Passed portable tests and macOS CI run 39334231361 |
| 4 | Named scene revision snapshots; restore/diff; MORE/CONT'D page continuations | Implemented; native validation in progress |
| 5 | Native spatial causality board; move cards; connect scenes; cycle validation | Pending |
| 6 | Native character/casting records and scene breakdown editing | Pending |
| 7 | Shooting-day assignments, call sheets and production exports | Pending |

Phase 3 keeps up to 40 project changes, coalescing a burst of edits to the same field within a second. Project undo uses Command+Option+Z and redo Command+Option+Shift+Z; normal Command+Z remains native text undo. Recovery copies are written after 800 ms without edits to Application Support/Frontstage/Recovery/session.frontstage, never to an imported source. Recovery is not a replacement for saving: the most recent fraction of a second can be lost in a crash. Startup asks whether to recover or discard the copy. Successful saves and explicit discard clear it. Test workspaces use injected stores and do not write to the real user's app directory.
