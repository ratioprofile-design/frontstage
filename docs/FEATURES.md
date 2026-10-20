# Implementation inventory

Updated 20 October 2026. “Implemented” describes executable workflows, not completed Causality/Backstage parity or public-release approval.

| Area | Delivered | Remaining gate or limitation |
| --- | --- | --- |
| Native Mac app | SwiftUI/AppKit/TextKit; universal development bundle | Hands-on Apple Silicon/Intel installation and accessibility |
| Whiteboard | Default gray canvas; colored stacked beats, blocks, nested groups/layers, timeline and optional side panels | Visual/reference comparison and full native gesture acceptance |
| Floating beat editor | Stable snippet identity, rich text, title/synopsis, characters/tags/type/cause flag, split, live undo/recovery | Exact Causality popup appearance and IME/focus/manual review |
| Board editing | Multi-selection, marquee, block/group moves, multi-snippet reorder, insert before/after, nesting, collapse, locks, zoom/pan/fit, drag/inspector width resize, arrow-key navigation, accessible beat actions, annotation strokes | Real-device accessibility review, richer drawing tools, complete context-menu parity |
| Cause/effect engine | Causal versus reference links, missing-cause badges, topological ripple, converging causes, cycle rejection, atomic lock failure | Causality-specific undocumented rules, backward compaction and behavior reference |
| Linked screenplay | Stable snippet IDs independent of scenes; split/merge/reorder, timeline-order application, source-aware revisions | Full act/readability/tension tracks and proprietary format support |
| Screenplay editing | Semantic paragraph types, headings/numbers, native formatting/undo, Unicode | Unsupported imported HTML/style/media fidelity review |
| Layout and writing | Custom font/size/line height, Bamini conversion, two-column writing/PDF, script locks and explicit page starts | Dual dialogue, frozen page numbering and production revision marks |
| PDF and print | Letter/A4, orphan prevention, MORE/CONT'D, native printing | Visual print/typography/manual printer checks |
| Projects and recovery | Atomic copies, protected source files/symlinks, unknown-field retention, bounded undo, debounced recovery | Crash/relaunch and legacy fixture acceptance on installed app |
| Revisions | Named scene snapshots, diff, backup-before-restore, snippet-boundary restore | Complex imported revision formats |
| People and breakdown | Character discovery/profiles, role assignments, casting contacts/status, manual requirements | Advanced audition workflows and provider integrations |
| Research/media | Scene/beat-linked records, crew/continuity/shot/audition fields, embedded attachments, image preview/export, CSV | Dedicated advanced production UI, large external asset storage |
| Production | Shooting days, ordering/durations, cast calls, workload/turnaround diagnostics, call sheets, DOOD, CSV/XLSX | Constraint scheduling optimizer, location/maps services |
| Interchange | Project JSON; text/RTF/PDF/DOCX text import; DOCX screenplay export; CSV/XLSX first worksheet; attachment portability | Scanned PDF OCR, full Office styling/formulas/multiple sheets, native Causality files |
| Native drawing | Persisted freehand whiteboard annotations | Full Excalidraw-equivalent objects, selection and export |
| Service | Swift/Vapor accounts, bcrypt, expiring hashed sessions, project permissions, atomic CAS revisions and retry IDs | Hosting, TLS proxy, backups, rate limits, account recovery and operations review |
| Mac sharing | Keychain session, shared create/open, owner access controls, reader pull, explicit push/pull, three-way conflicts/backups | Background sync and cold offline shared-session restoration |
| Browser | Whiteboard/popup/script, causes, ownership sharing, offline drafts/reconnect merge; Vercel static build and separate-origin service support | Verify public deployment, provision persistent backend, complete Mac/production/nested-group parity and cold offline launch |
| Windows | Native Win32 board/popup/project save/undo and shared Swift engine; CI UI smoke | Rich screenplay text, sync UI, full Mac workspace parity, installer/accessibility |
| Public distribution | Universal Mac development builds, Windows development zip, container build, signing/notary script | Actual Developer ID signing/notarization, clean-machine installers and updates |

Known legacy credential fields are stripped. This is not a general secret detector. Mac service sessions use Keychain; browser session tokens are held in memory. Retaining serialized fields does not implement the corresponding legacy feature.
