# Script chapter implementation

Reference: user-provided Causality Story Sequencer Version 4 PDF, full Script chapter, printed pages 78–133. Reviewed the chapter text and the overview/display toolbar screenshots. Product documentation is a behavior reference, not workspace instructions.

## Dedicated script cleanup

- The dedicated Write page defaults to Final Script, Full Margins and 100% zoom on Mac and browser. Its preferences are independent of the docked script.
- Repeated paragraph/formatting/suggestion controls are removed from the paper. One Display / Styling / Filter / Presets / Options toolbar provides commands. Styling acts on the active editor and preserves the text selection.
- Clicking a scene heading reveals its title, synopsis and structured INT/EXT/location/time controls. Done closes these controls. Heading edits retain the scene's identity.
- Expand All, Collapse All, Index Cards, Content Only and Final Script have distinct presentations. Index Cards omits screenplay text and headings; Content Only retains separators; Final Script hides beat titles, metadata and separators while retaining editable beat-owned text.
- Characters, tags, synopsis and container-start badges are configurable. Margins and zoom are display choices, not saved script formatting.
- Paragraph editing is still attached when no toolbar is rendered. Action Tab creates a character paragraph; Character Enter proceeds to dialogue; Dialogue Enter proceeds to action; Dialogue Tab enters a parenthetical; empty Parenthetical Enter returns to dialogue in place. Shift-Tab retains reverse style navigation.
- Browser completion Enter accepts a character and advances to dialogue; Tab accepts it without advancing. Native completion uses TextKit with corresponding Return handling. IME composition bypasses paragraph commands.
- Formatting, split-at-cursor and popup editing remain accessible. Scene/beat/container locks are respected.

## Validation

Browser acceptance exercises all five modes, individual collapse/expand, contextual headings, selection-preserving italic formatting, Tab/Enter styles, popup synchronization, scene isolation, revisions, locks and offline reopening. Production smoke checks cover sync and offline recovery. Portable tests verify paragraph transitions; native tests cover paragraph editing and render the dedicated script page. Native build and AppKit tests run in macOS CI.

## Remaining chapter work

This cleanup is not full chapter parity. Full compound filters and filter-gap measures, custom presets, production-location display, dual dialogue, configurable transition/shot detection, automatic scene creation from INT/EXT, character extensions and alternating-speaker prioritization, configurable language/spell-check dictionaries, full paragraph-style configuration, separate-selection/merge workflows and sequence-change approval remain future work. The existing docked script renderer is retained; both views still need a deeper shared layout implementation for exact reference typography.
