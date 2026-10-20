# Release and installation gates

The macOS CI builds a universal Apple Silicon/Intel development app. Its ad-hoc signature is not a Developer ID signature, notarization or an installation test on a clean Mac.

For a distributable macOS build, configure a Developer ID Application identity in the signing machine's Keychain, and an existing `notarytool` profile using Apple's secure credential workflow. Do not put credentials in source files or chat. Then run:

```sh
FRONTSTAGE_SIGNING_IDENTITY='Developer ID Application: Your Organization (TEAMID)' FRONTSTAGE_NOTARY_PROFILE=frontstage ./scripts/notarize-macos-app.sh
```

The script builds both architectures, enables hardened runtime and timestamping, submits to Apple, staples the accepted ticket, assesses the app with Gatekeeper and creates `build/Frontstage-macOS-notarized.zip`. It does not publish a release or deploy anything. The signing and notarization branch cannot be executed without the owner's Apple Developer configuration; it is not currently verified. The ordinary development build remains tested separately.

Native Windows builds run in `windows.yml`, using a pinned Windows Swift setup action. The executable uses Win32 for the board, file dialogs and a floating beat editor, sharing the Swift project/whiteboard/causality code. This first Windows client has plain-text snippet editing: original HTML is kept until its text changes. Rich screenplay formatting, complete Mac workspace parity, sync UI, installer/update code, accessibility and hands-on Windows verification remain outstanding. The workflow collects the executable and discovered Swift runtime DLLs as a development artifact; runtime dependency/license packaging and clean-machine installation must be reviewed before distribution.

Mac manual gates remain: popup keyboard focus/IME and undo; drag at different zoom levels; split/reorder/merge and source protection; imported language/format fidelity; PDF and two-column print output; sync conflicts; crash/relaunch recovery; accessibility and performance. Automated screenshots exercise construction and selected interactions; they do not certify the whole product against Causality.

For browser/server setup and limits see [Server README](../Server/README.md). Public hosting, HTTPS, registration policy and operational backups need a chosen deployment environment. No public site, production account or Windows/macOS installer is implicitly created by source commits.
