# DOT

A native Swift macOS writing and production app with a whiteboard-first story workspace. All development is in [ratioprofile-design/frontstage](https://github.com/ratioprofile-design/frontstage); the original Backstage repository is unchanged.

The whiteboard and floating beat editor are the primary workflow. This is a working development build, with remaining parity and release gates recorded in [the phase checklist](docs/ROADMAP.md). Exact Hollywood Camera Work Causality parity has not been established.

## Preview

On [GitHub Actions](https://github.com/ratioprofile-design/frontstage/actions/workflows/swift.yml), choose a successful **Swift** run and download **DOT-macOS-development** while signed into GitHub. Unzip the download, then the enclosed `DOT-macOS.zip`, and open `DOT.app`. Requires macOS 14+. These are ad-hoc signed development builds; Developer ID distribution/notarization is pending.

To build on a Mac with Swift 6 / Xcode 16+:

```sh
swift test
./scripts/build-macos-app.sh
open build/DOT.app
```

The bundle contains arm64 and x86_64 executables. Linux runs the portable tests and server; it cannot display the Mac app.

## Working features

- Gray whiteboard, compact colored snippets in blocks, nested groups, named layers, timeline/character tracks, optional left script and right properties panels.
- Native floating rich-text beat editor: double-click a beat or press Return. Title, synopsis, story/subtext type, characters, tags, cause requirement and split at cursor use stable snippet IDs.
- Multi-selection, block/group movement, snippet reordering between blocks, insert before/after, grouping, collapse, locks, cursor-centered zoom, pan, fit and freehand annotations.
- Causal/reference links, missing-cause diagnostics, cycle rejection, deterministic forward ripple, atomic rollback at locked blockers and explicit timeline-to-script ordering.
- Editable act markers, group/ungroup and protected block deletion, rigid boundary movement and explicit causal-time compaction. PDF/DOCX preserve interleaved snippet order and returning scene numbers.
- Native screenplay elements, headings, scene numbering, rich-text undo, revisions, recovery, typography, Bamini-to-Unicode conversion and two-column writing.
- Letter/A4 screenplay PDF/print, MORE/CONT'D, explicit scene page starts and script text locks. Dual dialogue and locked production pagination remain pending.
- People/casting, breakdowns, shooting days, call-sheet PDFs, DOOD and CSV/XLSX reports.
- Research, crew, continuity, shots/storyboard attachments and auditions with media import/export; these are initial workspaces with remaining advanced parity work.
- Project copies, atomic `.frontstage` saves and unknown-field preservation; text/PDF/RTF/DOCX import, screenplay DOCX export and first-worksheet CSV/XLSX import.
- Swift shared-project server, Mac Keychain login, owner/editor/reader permissions, explicit synchronization, three-way merges and retained local conflicts.
- Browser grouping/markers, undo/redo, movable popup, snippet-aware reconnect merging and local offline startup after an initial online visit. Native Swift/Win32 Windows whiteboard/popup preview uses the same Swift domain code.

See [feature coverage](docs/FEATURES.md), [whiteboard behavior](docs/CAUSALITY.md) and [validation evidence](docs/VALIDATION.md).

## Save and editing behavior

Imports open as copies. Choose a new save destination; the app refuses `.backstage` save targets and project-target symlinks. Untouched legacy HTML and unknown fields are preserved. Native editing normalizes supported screenplay paragraph types and inline bold/italic/underline; unsupported styles need review.

Command+Z is text undo; Command+Option+Z is project undo. Recovery is a separate debounced copy, not an automatic save to the imported source. Unreadable recovery data is kept instead of overwritten.

## Shared projects and other platforms

[Server setup](Server/README.md) covers local browser preview, accounts, persistence, Docker and synchronization. Run the service locally, then visit `http://127.0.0.1:8080`. The persistent shared service has not been deployed.

The browser is available at [frontstage-five.vercel.app](https://frontstage-five.vercel.app/), with static delivery verified by the Browser deployment workflow. Its Vercel project is connected to this repository. A persistent Swift backend and its HTTPS origin are still required for public accounts/sync. See [Vercel setup](Server/README.md#vercel-browser-deployment).

Choose **Use on This Device** on the browser sign-in screen to work without an account or backend. Add a block/beat, double-click it for the popup, and use **Download Project** for a portable `.frontstage` copy. Local projects persist in this browser and reopen from the same button; clearing browser/site storage removes those local copies. A separate backend is required only for shared accounts and synchronization.

Mac and Windows clients are Swift executables without an embedded web runtime; the service is Swift/Vapor. The browser presentation uses HTML/CSS/JavaScript and shares the document/service contract.

Windows development artifacts are on [the Windows workflow](https://github.com/ratioprofile-design/frontstage/actions/workflows/windows.yml). The Windows preview has plain-text snippets and a subset of the Mac workspace; it is not yet a complete Windows release.

[Release gates](docs/RELEASE.md) cover Apple signing, hosting, installation, accessibility and remaining client parity.

## DOT branding and project compatibility

DOT saves new projects as `.dot` and continues to open `.frontstage` projects. Word templates also use `.dot`; DOT checks the file contents and never treats a Word template as a project. Internal bundle, storage, recovery, Keychain and project-format identifiers retain their original names so existing data remains accessible. The repository and website address remain unchanged.

Icons follow system appearance; active controls use the system accent (browser system highlight when the exact OS accent is unavailable). Paper themes and user-assigned story colors are independent. Future themes can use the semantic `--dot-accent`, `--dot-on-accent` and `--dot-selection-tint` tokens; this release does not load community plugins.

The supplied originals and their hashes live in `Resources/Brand`. To regenerate resized platform assets without redrawing the artwork, install Pillow and run `python3 scripts/build-brand-assets.py`. The Dock filenames supplied by the owner are reversed relative to their artwork; `artwork.json` records the explicit mapping.
