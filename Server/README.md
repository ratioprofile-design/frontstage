# Shared projects and browser client

The Swift/Vapor service stores accounts, hashed session tokens, project memberships and versioned documents in an app-owned JSON store. Passwords use bcrypt. An actor serializes atomic file writes and compare-and-swap revision updates. This initial service is intended for a single process with a persistent local volume; it is not a distributed database or a horizontally scaled deployment.

Run from this directory with a Swift 6 toolchain:

```sh
swift build -j 3 --force-resolved-versions
FRONTSTAGE_DATA_DIR=/absolute/path/to/frontstage-data FRONTSTAGE_ALLOW_SIGNUP=1 .build/debug/FrontstageServer serve --hostname 127.0.0.1 --port 8080
```

The browser client is served at the root. Create accounts while registration is enabled, then restart without `FRONTSTAGE_ALLOW_SIGNUP=1` to close registration. The app does not create an initial user or print credentials. Log in from **Shared Projects** in the Mac client using the same server address. Create a shared copy or open an existing project, and synchronize explicitly. Owners share with registered accounts as editors or readers. The browser synchronizes after edits and polls for remote changes when it has no local work or popup open.

Documents use the same `.frontstage` schema as the Mac client. Stale revisions return HTTP 409 with the latest document. Clients merge independent fields and entity IDs; overlapping changes need a choice. Browser drafts are saved in IndexedDB before upload, and Mac edits remain local with the existing recovery mechanism. Download a `.frontstage` backup from the browser at any time. Neither client silently resolves conflicting text by overwriting it.

The browser uses JavaScript for its presentation layer. The Mac and Windows executables remain native Swift; no browser runtime is embedded in them. The browser currently covers the whiteboard, beat popup, causal ordering, script snippets, sharing and offline edits in an already loaded tab. Cold offline launch, all desktop production features, full nested-group operations and complete rich-text/gesture parity remain outstanding.

Session tokens stay in browser memory, and the Mac client uses Keychain. Browser sign-out retains offline drafts on the device; do not use a shared OS/browser profile for private projects. The service defaults to loopback HTTP for local development. A remotely accessible installation needs a configured HTTPS reverse proxy, backups, domain and host account; these are not provisioned by committing this repository. The native client rejects remote plaintext HTTP.

The data directory contains sensitive projects and password hashes. Keep it on a private persistent volume; backup/restore the entire store while the process is stopped. Do not run multiple server instances against the same file. Per-file attachments are limited to 10 MB and total embedded media to 64 MB per project. Request bodies are limited to 96 MB. Signup and login rate limiting, audit logs, recovery/email verification, hosting monitoring and production security review are still release work.

Validate locally from the repository root after building:

```sh
python3 Server/Tests/smoke.py
node Server/Tests/merge.mjs
```

For browser interaction tests, install Playwright in `Server/Tests`, install Chromium using Playwright, then run `node Server/Tests/browser-smoke.mjs`. The CI workflow installs these dependencies and uploads `browser-whiteboard.png` and `browser-popup.png`. The smoke scripts use temporary data, create synthetic accounts, and clean up their own server processes.

Docker build (from repository root): `docker build -f Server/Dockerfile -t frontstage-server .`. Mount a persistent volume at `/data`; enable account registration only while enrolling users. A committed Dockerfile is not evidence of a deployed or reviewed production service.
