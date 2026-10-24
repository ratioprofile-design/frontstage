# Remaining phases

Updated 24 October 2026. These are remaining completion gates, not a claim that previously implemented features are absent. Whiteboard remains the highest priority. See CAUSALITY_MANUAL_IMPLEMENTATION.md for the detailed manual comparison.

1. **Whiteboard and timeline completion.** Live Push preview and collision packing; container endpoint dependencies and dependency navigation; FlowLines and character/tag coloring; nested research folder ordering and composite curves; automatic tension rules and readability; actual typeset-page timing; script-workspace mini-timeline and complete episode title-page semantics.
2. **Screenplay and production completion.** Dual dialogue, frozen production pagination and revision marks; full typography/printing and Office fidelity; advanced scheduling, production and drawing tools. Verify multilingual input and screenplay suggestions on an installed Mac.
3. **Mac/browser acceptance.** Compare the same project and interactions across both editions; check small and multiple screens, keyboard/accessibility, trackpad gestures, popup focus and printing. Automated tests support this gate but do not replace hands-on acceptance.
4. **Shared projects in production.** Provision a persistent backend and HTTPS hostname; finish authenticated offline session restoration and account lifecycle; add rate limits and monitoring; perform multi-device sync, conflict and backup/restore acceptance. The Vercel browser frontend alone does not complete this phase.
5. **Windows parity.** Bring rich screenplay editing, sync, workspaces and gestures to parity with Mac/browser; validate Windows installation and UI behavior.
6. **Release.** Configure the owner's Mac signing identity and notarization profile in the release environment; produce signed/notarized builds and verify clean-machine installation. Development CI artifacts are previews.

Recommended order: finish the whiteboard/timeline interaction work first, then screenplay and cross-platform acceptance, followed by production sharing, Windows parity and release certification.
