# Migration status

| Area | Status |
| --- | --- |
| Native macOS shell and scene list | Implemented; macOS CI build passed, interactive runtime review pending |
| Scene title, summary, native rich text | Implemented; macOS TextKit/workspace tests passed, interactive import fidelity review pending |
| Project create/import/save | Implemented; portable model tests cover source protection |
| Unknown project fields, Tamil HTML preservation | Implemented in portable model; rich-text edit fidelity needs macOS checks |
| Credentials | Known legacy fields stripped; Keychain/provider integrations not implemented |
| Undo | TextKit text undo only; project-wide undo not implemented |
| Screenplay element editing, pagination, revisions, print/PDF | Not implemented |
| Causality timeline, spatial board, Excalidraw replacement | Not implemented |
| Tamil/Bamini conversion and two-column editor | Not implemented |
| Character/casting/crew/breakdown/continuity | Not implemented |
| Shots, storyboards, production plan, DOOD, call sheets | Not implemented |
| Vault, DOCX/XLSX/PDF imports and exports | Not implemented |
| Cloud auth, sync, collaboration and permissions | Not implemented |
| Web and Windows clients | Future separate clients; not implemented |
| Packaging for public distribution and notarization | Not implemented |

Retaining a feature's serialized fields is not the same as implementing that feature.
