# Native macOS migration preparation

Status: first Swift foundation implemented in frontstage; full migration is outstanding. See FEATURES.md and VALIDATION.md for current scope and evidence.
Source inspected: ratioprofile-design/Backstage, commit 425da0c30eb3d10b47f3398dbc909989fe761d69.
The original checkout is read-only for this migration. All implementation belongs in a new independent repository under the GitHub owner and name selected by the user. Do not push to, rename, move, or alter the source repository. Do not copy its Git metadata, local environment files, credentials, caches, generated output, or user project data.

## Architecture

Build a native macOS client with SwiftUI, using AppKit/TextKit for advanced screenplay editing, printing, keyboard behavior, and document windows where appropriate. Use Foundation for project serialization, file operations, and networking. This is a rewrite, not a React view embedded in a web view.

Separate a Foundation-only domain package from macOS presentation and service adapters. Keep the persisted document schema and service contracts independent of SwiftUI. SwiftUI does not provide a Windows or browser UI: future clients require their own presentation layers. Swift on Windows can potentially reuse compatible domain code, subject to platform tests; do not assume Apple frameworks are available there.

Selected future browser model: shared projects and synchronization through a common authenticated backend, rather than hosting a running Mac for each browser session. Define authentication, permissions, revisions, conflict handling, and asset URLs as shared contracts. A Swift backend is possible, but existing Supabase services can remain during migration. Replacing every existing backend is a separate scope decision.

If the user means remote UI streaming instead, plan Mac hosting capacity, session isolation, input forwarding, video transport, reconnect behavior, and operating costs separately. Do not implement a sync architecture while presenting it as remote streaming.

## Source inventory and intended native replacements

| Existing area | Native migration work |
| --- | --- |
| App.tsx, navigation and React contexts | SwiftUI app scenes, navigation, explicit observable project/session state, native commands and undo management |
| types.ts and ProjectContext.tsx | Codable domain types, defaults, validation, migrations, change tracking and project repository |
| ScriptEditor and script views | AppKit/TextKit screenplay editor, pagination, scene elements, revisions, print/export |
| CausalityCanvasBoard and causality engines | Native board rendering, hit testing, drag/zoom, lanes, connections and Swift algorithms |
| ExcalidrawBoard | Native drawing/document model or explicitly planned replacement; Excalidraw is a JavaScript dependency |
| Tamil, Bamini, two-column services | Swift Unicode conversion and layout, tested against representative source fixtures |
| Breakdown, casting, crew, continuity | Native feature views and domain operations |
| Shot lists, storyboards | Native media/shot views with optional AI service adapters |
| Schedule, DOOD, call sheets | Native planning models, views and print output |
| Vault, PDF, DOCX, spreadsheet import/export | PDFKit and native file APIs; choose and test non-JavaScript DOCX/XLSX support explicitly |
| localRustStorage and src-tauri/storage.rs | Native atomic file writes and local project index; do not reuse the old app's default directory for new writes |
| Supabase, AI providers, Maps, R2 | Swift network adapters, account/session handling and Keychain or server-managed credentials |

## Compatibility requirements

The existing .backstage files are JSON. Beat IDs are numeric, with board coordinates, slugline objects, HTML content, nested shots, breakdown data, versions and optional fields. Project state also includes causality lanes/groups/breaks, annotations, character data, settings, Tamil dictionaries, talent and documents. Project data exists across disk, IndexedDB, localStorage and cloud paths; audit export completeness before promising complete migration.

Initial import must preserve unknown fields and rich-text source so a partial migration cannot silently erase unsupported content. Keep the original file untouched; import to a new file with a separate app directory and explicit format version. Define conversions from existing HTML to native attributed text with fixtures for scene headings, dialogue, lists, Tamil text and embedded content. Test saving/reopening and compatibility, not just successful JSON decoding.

Some legacy project serialization includes API-key fields. Imported credentials must not be logged, committed, synchronized or exported by default; move supported local credentials to Keychain with explicit user handling. Do not include real project files in tests without sanitization.

## Implementation sequence and acceptance gates

1. Establish the new repository identity and authorized GitHub access. Create a fresh independent repository, macOS app target, domain package and macOS CI. Confirm the original checkout remains clean. The user supplied ratioprofile-design/frontstage; its existing empty repository has been cloned.
2. Deliver a native vertical slice: create/open/save a project, list/edit scenes, persist native screenplay content, import representative legacy JSON without data loss, and support undo. Build and run on macOS; run serialization and atomic persistence tests.
3. Port screenplay layout, revisions, Tamil conversion, two-column editing, PDF/print output, causality board and drawing features. Validate behavior and document fidelity using fixtures and user workflows.
4. Port casting, production planning, call sheets, vault, media and remaining utilities. Maintain a feature parity checklist with working, partial and unimplemented states.
5. Add authenticated cloud synchronization with conflict tests and offline/reconnect checks. Add optional provider integrations without embedding private credentials in the client.
6. Implement browser and Windows clients against the stable document/service contracts when requested. They are separate deliverables, not automatic output from SwiftUI.

Do not describe a shell or first vertical slice as the completed conversion. Full migration requires parity review across these feature areas.

## Validation limits

The current development host is Linux. A signature-verified Swift 6.0.3 Linux toolchain was installed and the 11 portable XCTest tests pass; Xcode is unavailable. It cannot compile or run SwiftUI/AppKit, sign or notarize macOS apps. Foundation-only tests may run on Linux after installing a supported Swift toolchain; native app readiness requires a Mac or macOS CI. GitHub write access and macOS CI results must be verified separately. Existing platform Git HTTPS read access to the original repository does not imply GitHub API access or permission to create a repository under another account.
