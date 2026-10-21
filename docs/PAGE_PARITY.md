# Mac and browser workspaces

The Mac and browser editions use the same ten workspace names, order, project format, dark chrome, and screenplay paper measurements. Whiteboard remains the default. `Design/workspaces.json` is the source for generated Swift constants and browser CSS/JavaScript. Regenerate with `node scripts/generate-workspace-design.mjs`; CI checks for drift.

| Workspace | Browser implementation aligned with Mac |
| --- | --- |
| Whiteboard | Existing linked board, properties, timeline and optional script panel; workspace navigation keeps the board first |
| Write | Continuous screenplay, scene headings, semantic paragraph formats, bold/italic/underline, beat-linked popup opening and live text synchronization |
| Pages | Letter/A4 paper, measured pagination, explicit scene page starts and browser Print / Save PDF |
| Revisions | Named scene snapshots, comparison, restore with a safety snapshot and stable snippet references |
| People | Character profiles/discovery, casting options, contacts, status and confirmed actors |
| Breakdown | Scene role assignments and categorized production requirements |
| Production | Shooting days, assignment/order/estimates, location/crew/cast fields, schedule checks, schedule CSV, day-out-of-days codes and printable call sheets |
| Writing Tools | Text/heading locks, page starts, typography, Bamini conversion and parallel translation rows/printing |
| Research & Studio | Research, crew, continuity, shots and auditions; linked scenes, embedded files, image previews and CSV |
| Shared Projects | Local backups, server connection, explicit synchronization/refresh, shared copies and owner access changes |

## Verification

`node Server/Tests/workspace-model.mjs` checks model operations. `node Server/Tests/workspace-parity.mjs` opens every page with one checked-in project, exercises editing across pages, verifies simultaneous Write/popup updates, exports the result, checks long-script pagination and reopens offline. It generates browser screenshots and `browser-edited.frontstage` in `build/parity`.

On macOS, `WorkspaceParityAcceptanceTests` renders every page and the popup using the same project. `WorkspaceParityTests` reads the actual browser-edited export and verifies casting, breakdown, revisions, typography, translation, production and attachments before another save/reopen.

The Swift workflow publishes **Frontstage-page-parity**. Download and unzip it, then open `index.html` to compare paired captures. Mac window decorations and native controls are platform-specific. Screenshots are review evidence; their existence alone does not establish pixel-identical layouts or identical text shaping.

For local verification:

```sh
node scripts/generate-workspace-design.mjs --check
node Server/Tests/workspace-model.mjs
# Install Playwright in Server/Tests and its Chromium runtime first.
node Server/Tests/workspace-parity.mjs
FRONTSTAGE_PARITY_DOCUMENT="$PWD/build/parity/browser-edited.frontstage" \
FRONTSTAGE_PARITY_OUTPUT="$PWD/build/parity" swift test
```

## Remaining acceptance and differences

- Compare the paired screenshots and test native focus, Tamil IME, printing and accessibility on an installed Mac. Browser font metrics can produce different line/page breaks; native MORE/CONT'D pagination and Office interchange are not fully reproduced by browser printing.
- Browser page availability is implemented. Full native gesture/drawing parity, advanced production tools, cold offline shared-session restoration and Windows workspace parity remain separate work tracked in `ROADMAP.md`.
- The Vercel domain serves the browser edition. Multi-device sharing still requires a persistent Swift service; release signing/notarization still requires the owner's release configuration.

No changes are made to the original Backstage repository.
