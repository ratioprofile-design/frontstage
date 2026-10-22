# Phase completion and remaining gates

Updated 22 October 2026. The whiteboard remains the highest priority, followed by the popup editor. All changes belong to Frontstage; Backstage remains untouched.

The implementation now spans every planned phase. The acceptance gates below remain open where reference behavior, real-device review, additional implementation or owner configuration is still required. This is not a declaration that every phase is complete.

Current close-out evidence and remaining gates are recorded in [the completion ledger](PHASE_STATUS.md).

## Whiteboard phases

| Phase | Delivered | Required before full acceptance |
| --- | --- | --- |
| 8 — Foundation/layout | Default gray whiteboard, stacked colored snippets, translucent blocks/title tabs, named layers, top timeline and optional panels; versioned additive schema | Compare whole-window native captures with both supplied layouts and representative imported projects |
| 9 — Popup editor | Multiple independent native/browser floating editors with screenplay paper, stable beat identities, standalone beat creation, live edits, split, characters/tags/type/cause flag; identity test and screenshot | Open-editor reference image/recording; hands-on IME, focus, dismissal and undo review |
| 10 — Board interactions | Group/ungroup, nested rigid movement including boundary clamping, protected block/content deletion, multi-selection, marquee, multi-snippet reorder, before/after insertion, collapse/locks, pan/zoom/fit, viewport, width resize, keyboard/accessibility and annotations; browser group/undo/redo workflows | Full gesture acceptance and remaining context actions; measure interactive rendering/accessibility on real Mac |
| 11 — Cause/effect | Causal/reference edges, must-cause flag, missing-cause badges, cycles, forward ripple, explicit earliest-time compaction with locked starts, atomic rollback | Compare repair/ripple/compaction behavior with Causality; undocumented proprietary rules remain unverified |
| 12 — Linked script/timeline | Stable snippets/scenes; split/merge/reorder, synced surfaces, character tracks, editable act markers/guides, explicit narrative order, interleaved scene ranges in PDF/DOCX with preserved numbering, research and revisions | Hands-on native acceptance and reference-based readability/tension calculation |

The supplied second image shows a context menu, not the open popup text editor. Exact popup geometry and interactions cannot be verified from it. Static screenshots also do not specify proprietary cause/effect rules.

## Subsequent phases

| Phase | Delivered | Required before full acceptance |
| --- | --- | --- |
| 13 — Screenplay | Bamini conversion, two-column writing/PDF, typography, scene text/heading locks, explicit scene page starts and revisions | Dual dialogue, frozen production pagination/revision marks, imported fixture/print review |
| 14 — Production/media | Crew, continuity, shots/storyboard attachments, auditions, research/media storage, DOOD, call sheets and reports | Dedicated advanced workspaces, scheduling optimizer, representative production workflow acceptance |
| 15 — Interchange/drawing | DOCX screenplay export/import, PDF/RTF/text import, CSV/XLSX first-sheet import/export, portable embedded media, freehand annotation | Full Office/media fidelity, richer drawing, original Causality format support only after format/files are available |
| 16 — Mac release | Universal development bundle, automated native tests, screenshot/PDF artifacts, 10,000-beat geometry test, Developer ID/notary script | Real Mac accessibility/input/performance/recovery checks; Apple identity/profile, actual notarization and clean-machine install/update |
| 17 — Sharing | Swift/Vapor backend, accounts/permissions, CAS/retries, three-way merge/conflict backup, Mac Keychain; independent same-scene snippet edits merge before scene text is rebuilt, genuine text/lock conflicts retained | Persistent backend host/HTTPS, backups/account lifecycle/rate limits, background sync and cold offline shared-session restoration |
| 18 — Browser | Gray board/popup/script, groups/ungroup/undo/redo, causal compaction, act markers, movable popup, local/shared projects and reconnect merge; cached local app startup/reload offline after an initial visit | Page-by-page visual acceptance, advanced production/gesture parity, shared-session offline restoration, broader browser/input/accessibility checks |
| 19 — Windows | Native Swift/Win32 board/popup, shared model/solver, protected project import/save, native UI smoke and development artifact | Rich script editor, sync UI, production workspaces, clean-machine runtime/installer/licensing and accessibility |

## Mac/browser workspace alignment

The browser now exposes all ten Mac workspaces, backed by the native project schema. Write is a continuous screenplay on both platforms; Pages remains the paginated output view. Shared design constants, browser-to-native edited-file tests, and paired page capture artifacts are documented in [Page parity](PAGE_PARITY.md). This closes the missing-page implementation gap; it does not close the gesture, typography, Office interchange or installed-app acceptance gates above.

## Close-out order

The first milestone is tracked in [Whiteboard and editor acceptance](WHITEBOARD_ACCEPTANCE.md), separating automated regression checks from outstanding hands-on and reference checks.

1. Keep the native whiteboard/popup acceptance workflow and all platform checks passing; retain preview artifacts.
2. Use an actual open-popup reference and a behavioral Causality sample to close visual/interaction differences. Finish readability/tension tracks and remaining board actions according to that evidence.
3. Complete dual dialogue and frozen production pagination, then advanced production/drawing workflows with representative fixtures.
4. Complete browser and Windows workspace/sync parity, including cold offline restoration, and run cross-platform user acceptance.
5. Configure the owner's release/deployment environment, execute signing/notarization and installation checks, deploy the shared service behind HTTPS, and verify backups and multi-device operation.

No permission is needed for continuing authorized Frontstage implementation. Apple account configuration, a deployment target and missing reference behavior are specific dependencies; they do not make unrelated work complete.

Owner configuration update: the browser domain is `frontstage-five.vercel.app`, already connected to Frontstage/main on Vercel. The static browser build is configured; a persistent Swift backend host remains to be chosen. The owner will configure Apple signing in the release environment. No certificate, key or password belongs in chat or source.
