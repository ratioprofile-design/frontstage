# Implementation inventory

Updated 21 October 2026. “Implemented” describes executable workflows, not completed Causality/Backstage parity or public-release approval.

| Area | Delivered | Remaining gate or limitation |
| --- | --- | --- |
| Native Mac app | SwiftUI/AppKit/TextKit; universal development bundle | Hands-on Apple Silicon/Intel installation and accessibility |
| Whiteboard | Default gray canvas; colored stacked beats, blocks, nested groups/layers, timeline and optional side panels | Visual/reference comparison and full native gesture acceptance |
| Floating beat editor | Multiple independent paper editors, stable snippet identity, rich text, title/synopsis, characters/tags/type/cause flag, split, live undo/recovery; browser project undo retains open editors | Exact Causality popup appearance and IME/focus/manual review |
| Board editing | Standalone beats, snapped rigid standalone selection moves, multi-selection, marquee, rigid group moves, nested group/ungroup, protected block/content deletion, snippet reorder/insert, collapse/locks, zoom/pan/fit, width resize, keyboard/accessibility, annotations | Real-device accessibility review, richer drawing tools, complete context-menu parity |
| Cause/effect engine | Causal/reference links, missing-cause badges, topological ripple, converging causes, explicit earliest-time compaction, cycles and atomic lock failure | Causality-specific undocumented rules and behavior reference |
| Linked screenplay | Stable snippets independent of scenes; split/merge/reorder, editable act markers, timeline order, interleaved scene ranges in PDF/DOCX, source-aware revisions | Readability/tension tracks and proprietary format support |
| Screenplay editing | Semantic paragraph types, headings/numbers, native formatting/undo, Unicode | Unsupported imported HTML/style/media fidelity review |
| Layout and writing | Custom font/size/line height, Bamini conversion, two-column writing/PDF, script locks and explicit page starts | Dual dialogue, frozen page numbering and production revision marks |
| PDF and print | Letter/A4, orphan prevention, MORE/CONT'D, native printing | Visual print/typography/manual printer checks |
| Projects and recovery | Atomic copies, protected source files/symlinks, unknown-field retention, bounded undo, debounced recovery | Crash/relaunch and legacy fixture acceptance on installed app |
| Revisions | Named scene snapshots, diff, backup-before-restore, snippet-boundary restore | Complex imported revision formats |
| People and breakdown | Character discovery/profiles, role assignments, casting contacts/status, manual requirements | Advanced audition workflows and provider integrations |
| Research/media | Scene/beat-linked records, crew/continuity/shot/audition fields, embedded attachments, image preview/export, CSV | Dedicated advanced production UI, large external asset storage |
| Production | Shooting days, ordering/durations, cast calls, workload/turnaround diagnostics, call sheets, DOOD, CSV/XLSX | Constraint scheduling optimizer, location/maps services |
| Interchange | Project JSON with browser identifier/geometry/reference validation and transactional opening; unprojected scene text protected; text/RTF/PDF/DOCX import, DOCX export, CSV/XLSX first worksheet and portable attachments | Scanned PDF OCR, full Office styling/formulas/multiple sheets, native Causality files |
| Native drawing | Persisted freehand whiteboard annotations | Full Excalidraw-equivalent objects, selection and export |
| Service | Swift/Vapor accounts, bcrypt, expiring hashed sessions, project permissions, atomic CAS revisions and retry IDs | Hosting, TLS proxy, backups, rate limits, account recovery and operations review |
| Mac sharing | Keychain, shared create/open, owner access/reader pull, explicit sync, snippet-aware merge with genuine text/lock conflict retention | Background sync and cold offline shared-session restoration |
| Browser | Board/popup/script, group/ungroup/delete/undo/redo, markers/compaction, movable popup, local cold-offline reload/edit/export, sharing and snippet-aware reconnect merge; verified Vercel/separate-origin setup | Persistent shared backend, complete Mac/production/gesture parity, shared-session offline restoration |
| Windows | Native Win32 board/popup/project save/undo and shared Swift engine; CI UI smoke | Rich screenplay text, sync UI, full Mac workspace parity, installer/accessibility |
| Public distribution | Universal Mac development builds, Windows development zip, container build, signing/notary script | Actual Developer ID signing/notarization, clean-machine installers and updates |

Known legacy credential fields are stripped. This is not a general secret detector. Mac service sessions use Keychain; browser session tokens are held in memory. Retaining serialized fields does not implement the corresponding legacy feature.
