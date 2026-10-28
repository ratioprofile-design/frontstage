# Antigravity adoption into DOT

The reference is `ratioprofile-design/frontstagefordot` at `50ced9895e24e283afa348c31b394f6f609b18cf`. Integration started from canonical `frontstage` at `3c17478629402bef8599b89b3adefe8a9aed9a9a`, on `feat/antigravity-adoption`. The reference repository and Backstage remain unchanged.

## Compatibility

DOT retains bundle ID `design.ratioprofile.frontstage`, the existing credentials and storage paths, the native v1 envelope, supplied DOT artwork, system accent behavior, and `.dot` new-file defaults. Native `.dot` and `.frontstage` envelopes support ordinary Save. Legacy imports remain copy-only, including legacy JSON stored under a native-looking extension.

Mac Settings separates **Current project** typography from **Defaults for new projects**. The browser's Writing Tools can save current typography as device defaults explicitly. Defaults never restyle an opened project.

Mac Settings includes a one-time **Review Antigravity Settings** workflow. It recognizes documented app preferences in `design.ratioprofile.dot`, shows current/incoming conflicts, defaults to keeping current values, and backs up both reviewed preference sets before import. Credentials and AppKit rendering overrides are excluded. Backups live in `Application Support/Frontstage/Settings Backups`. Recent-project entries survive missing files; startup restoration is optional and recovery takes priority.

## Shared contracts

- `frontstageScriptLayout.elements` uses the reference's font, size, bold, italic, underline, uppercase and Tamil fields. Unknown settings survive edits. Disabling a known override archives extension metadata under `frontstageInactiveElementTypography`; re-enabling restores extension fields without restoring disabled font overrides. Missing fonts retain their stored names and display a fallback warning on Mac.
- `productionRevision` retains the reference's ID, color, label, millisecond date, baseline-lock flag and scene baseline map. Newly captured baselines also retain headings in `sceneBaselineHeadings`; legacy baselines without headings continue comparing their recorded body text. Previous raw baselines are retained in `productionRevisionHistory`. Color/label edits preserve revision identity and capture date. Scene stars and revision headers are generated presentation, not authored HTML.
- Paired speech paragraphs carry `sc-dual-left` / `sc-dual-right` plus `data-dual-pair`. Pairing requires two adjacent complete speech blocks in one scene. Moving complete scenes preserves identity; duplication allocates new pair IDs. A scene split through a pair is rejected until it is unpaired.
- **Review Legacy Dual Dialogue** previews normalization into a separate backed-up copy. Ambiguous annotations are rejected without changing the original. Mac adds identifiers directly to the original HTML so inline/imported extension markup is retained.
- Shared writes advertise supported features. The server rejects older clients when the previous or proposed document contains typography, baseline or dual-dialogue data the client cannot preserve.

## Workflow

The current agreed Enter/Tab rules, numbered element shortcuts, non-mutating suggestions, IME protection, caret handling, duplication and project undo/redo remain authoritative. Antigravity keyboard handlers were not copied over them.

Use the screenplay context menu or Cmd/Ctrl+Shift+L to pair/unpair the selected second speech block. Mac uses TextKit table cells for a common top; the browser keeps editable paragraphs flat and derives column geometry without replacing active nodes. Pages and exports group paired speech separately from authored text.

Mac Tamil switching is opt-in per element, suspended during composition, and restores only a source DOT actually changed. Browser Tamil settings adjust typography without changing the OS keyboard. Popup typography scales for reading without changing project settings.

Whiteboard Select/Draw/Eraser controls and middle-button panning are available in both editions. Erasing uses stroke/segment intersections and commits one undoable gesture. Permanent Research shelf deletion removes an unowned scene and its active references atomically, retains independent Research records/shared assets, and respects locks.

FDX and Fountain exports use shared paragraph fixtures for scene numbers, Tamil, emphasis, parentheticals, dual speech and continuation labels. Fountain adds a standard ignored boneyard comment to retain DOT's Shot type during its round-trip checks. Native project saving is separate from interchange export.

## Acceptance

`antigravity-contract.json` and `interchange-contract.json` exercise both implementations. Native hosted tests cover pairing/caret/undo, table geometry, DOCX cells and PDF text. Browser acceptance measures live columns, unequal multi-page speech, imported typography, baseline history/stars, drawing/erasing/panning and saved HTML. Existing Writer, popup, whiteboard, timeline, notes, offline and synchronization suites remain release gates.

Universal Mac packaging produces `DOT-macOS.zip` and a verified `DOT.dmg` with an Applications shortcut. Packaging does not register or install the app on the build machine.

Full frozen pagination, A/B pages and locked production numbering remain deferred. A baseline lock preserves a comparison baseline; it does not freeze pages.
