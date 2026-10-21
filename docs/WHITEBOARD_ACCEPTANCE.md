# Whiteboard and editor acceptance

The whiteboard is the first release milestone; popup editing is second. Automated tests below do not replace hands-on Mac acceptance or prove exact Causality parity.

## Automated regression checks

- Create independent standalone beats; save/reopen without changing scene identity or text.
- Keep two paper editors open, edit different snippets, close one, and retain the other.
- Browser project undo/redo retains surviving editors, their positions and refreshed content.
- Route Mac screenplay format commands only to the focused screenplay text view.
- Drag selected standalone beats together, snap consistently, preserve spacing at board boundaries, and reject locked or stacked selections atomically.
- Exercise actual native mouse events for a short multi-beat drag and restore positions with project undo.
- Exercise browser drag events with the original grab offset and multiple selected beats.
- Retain existing grouping, cause/effect, import, export, offline and concurrent-edit tests.

## Hands-on Mac checks still required

Record OS version, screen size, processor and build commit with each result.

1. Open three beat editors. Switch between them and the main screenplay, use format shortcuts, undo/redo, close the active editor and reopen it. Confirm each command affects the intended text.
2. Type Tamil and English, use an IME, paste formatted text, select across paragraphs and split at the caret. Confirm source text is preserved once in the linked script and PDF.
3. Drag loose beats, stacks and nested groups within and across layers. Check snapping, locks, boundary clamping, causal ripple and undo. Test mixed selections and cancelled gestures.
4. Test trackpad/mouse pan and zoom, multi-display window placement, small-screen paper scrolling and keyboard-only operation. Check VoiceOver labels and focus order.
5. Open a representative large project and measure interactive dragging, zooming and accessibility response. Geometry benchmarks alone do not establish interactive performance.
6. Save, force-quit, relaunch and recover a working copy. Reopen imports and compare exported screenplay text and ordering.

## Reference-dependent work

Compare the board against the supplied Causality layouts. An open-editor reference and behavioral examples remain necessary to assess exact popup appearance, snapping/ripple rules and readability/tension tracks. Until then these are functional Frontstage implementations, not verified exact matches.
