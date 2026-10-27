# Frontstage completion ledger

Updated 22 October 2026. This ledger covers the five requested close-out workstreams. **The full product is not release-complete.** Implemented features, automated evidence, deployment and manual acceptance are different gates. Original Backstage files remain untouched.

| Workstream | Implemented / fixed in this pass | Verification | Open gate |
| --- | --- | --- | --- |
| Whiteboard first | Browser forward ripple toggle; cross-lane block movement and rigid multi-loose-beat movement, preserving container identity/spacing and detaching a parent when appropriate | Browser operations test covers ripple, inherited locks, atomic rejection, cycles and cross-lane geometry; Chromium smoke/parity tests cover drag/undo/group/popup/script workflows | Hands-on Mac gestures, IME, accessibility, small/multiple screens; exact Causality comparison |
| Cause/effect | Browser movement uses the same forward-only timing rule as Swift, preserving deliberate gaps; compaction remains explicit | Existing Swift suite includes 10,000-beat causal/geometry checks; browser solver tests cover lock rejection and cyclic graph rejection | Causality's undocumented repair/readability/tension rules have not been established from behavioral reference material |
| Mac/browser alignment | Ten existing workspaces revalidated using one project, including scene-specific popup sluglines and screenplay suggestions | Browser-to-native exported fixture, page captures, continuous screenplay/popup synchronization and offline navigation | Full typography/printing/Office fidelity, advanced gestures and installed-Mac visual acceptance |
| Sharing | Recovery of cached shared drafts after cold offline startup as independent local projects; original shared draft/revision/base retained. Persistent HTTPS Compose configuration and backup/restore utility added | Cross-origin browser recovery test makes no API requests; backend smoke verifies permissions/CAS/conflicts/idempotency/restart/logout; backup tests verify private permissions, no overwrite and invalidation of restored sessions; Compose configuration validates | No persistent host/backend hostname provisioned. Authenticated offline session restoration, account lifecycle, rate limits, monitoring, production review and actual multi-device HTTPS/restore acceptance remain open |
| Releases / Windows | Manual signed/notarized Mac workflow for an owner-configured Keychain runner; Windows retains multiple independent editors and Enter creates a beat | Mac tests/build and Windows compile/UI-smoke are checked by CI on the published commit; local Linux cannot certify either native executable | Owner's signing runner/identity/profile, notarization, clean-machine installation. Windows still lacks rich screenplay, sync and full workspace/gesture parity |

## What the five workstreams do not close

27 October Write follow-up: the dual-dialogue shared document foundation is
implemented on a separate validation branch. Lossless Swift/JavaScript operations
and shared fixtures are available; editor controls, native/browser column layout,
and export support are still pending. It is not enabled or published. See
[the dual-dialogue checklist](DUAL_DIALOGUE.md) for the acceptance sequence.

Earlier phase milestones are implementation milestones, not proof of complete Causality equivalence. The remaining feature work in [ROADMAP](ROADMAP.md) still includes dual dialogue, frozen production pagination/revision marks, advanced production/scheduling/drawing, full Office fidelity and Windows parity. Missing hosting/signing configuration does not explain or close those implementation gaps.

## Reproducible evidence

- `swift test` with `FRONTSTAGE_PARITY_DOCUMENT` set to the browser-produced fixture: 115 portable tests passed in this pass. Native AppKit tests are separate macOS CI evidence.
- `node Server/Tests/board-operations.mjs`: movement, grouping, protection, ripple/compaction and cycle checks.
- `node Server/Tests/workspace-parity.mjs`: every browser page, linked screenplay/popup edits, slugline isolation, lane transfer, script highlight, undo and offline reopen.
- `FRONTSTAGE_STATIC_BROWSER=1 node Server/Tests/browser-smoke.mjs`: separate browser/server origins, accounts, merging, offline editing/recovery, locks and popup/board regression checks.
- `python3 Server/Tests/smoke.py`: restricted origin, auth, permissions, revision conflicts, idempotency, restart persistence and logout.
- `python3 scripts/test-server-backup.py`: backup/restore integrity and failure behavior.
- `FRONTSTAGE_SERVICE_DOMAIN=sync.example.com docker compose -f deploy/compose.yaml config --quiet`: configuration only; it does not deploy or prove a live HTTPS service.

CI artifacts are development previews unless the explicitly configured notarization workflow succeeds. Read [RELEASE](RELEASE.md), [deployment instructions](../deploy/README.md), [whiteboard acceptance](WHITEBOARD_ACCEPTANCE.md) and [page parity](PAGE_PARITY.md) for the outstanding acceptance procedures.
