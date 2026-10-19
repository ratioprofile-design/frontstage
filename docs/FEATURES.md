# Migration status

| Area | Status |
| --- | --- |
| Native macOS shell and scene list | Implemented; macOS CI build passed, interactive runtime review pending |
| Scene title, summary, native rich text | Implemented; interactive import fidelity review pending |
| Screenplay elements, scene headings, scene numbers | Implemented; native semantic import/edit/save tests added |
| Letter/A4 page preview, PDF export, native print | Implemented; multipage output, omitted-scene and orphan-cue tests added |
| Project create/import/save | Implemented; portable model tests cover source protection |
| Unknown project fields, Tamil HTML preservation | Implemented in portable model; rich-text edit fidelity needs macOS checks |
| Credentials | Known legacy fields stripped; Keychain/provider integrations not implemented |
| Undo and recovery | TextKit undo, bounded project undo/redo, app-owned debounced recovery and explicit startup recovery |
| Scene revisions and dialogue continuation | Named snapshots, text diff, backup-before-restore, MORE/CONT'D in PDF |
| Spatial causality board | Move/arrange cards, zoom, directed links, cycle validation/diagnosis, omission and script ordering |
| Custom layout settings, page locks, dual dialogue | Not implemented |
| Timeline lanes, ripple flow, group editing, Excalidraw replacement | Not implemented |
| Tamil/Bamini conversion and two-column editor | Not implemented |
| Characters, casting and scene breakdowns | Profiles, cue discovery, assignments, casting contact/status/confirmation, manual requirements |
| Crew and continuity workspaces, advanced auditions/media | Not implemented; crew contact fields are available on production days |
| Shooting plan and call sheets | Day assignments/order, duration estimates, call times, basic workload/turnaround checks, printable call-sheet reports, schedule/breakdown CSV |
| Shots, storyboards, DOOD and scheduling optimizer | Not implemented |
| Vault, DOCX/XLSX/PDF imports and exports | Not implemented |
| Cloud auth, sync, collaboration and permissions | Not implemented |
| Web and Windows clients | Future separate clients; not implemented |
| Packaging for public distribution and notarization | Not implemented |

Retaining a feature's serialized fields is not the same as implementing that feature.
