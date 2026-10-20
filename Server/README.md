# Shared projects and browser client

The Swift/Vapor service stores accounts, hashed session tokens, project memberships and versioned documents in an app-owned JSON store. Passwords use bcrypt. An actor serializes atomic file writes and compare-and-swap revision updates. This initial service is intended for a single process with a persistent local volume; it is not a distributed database or a horizontally scaled deployment.

Run from this directory with a Swift 6 toolchain:

```sh
swift build -j 3 --force-resolved-versions
FRONTSTAGE_DATA_DIR=/absolute/path/to/frontstage-data FRONTSTAGE_ALLOW_SIGNUP=1 .build/debug/FrontstageServer serve --hostname 127.0.0.1 --port 8080
```

The browser client is served at the root. Create accounts while registration is enabled, then restart without `FRONTSTAGE_ALLOW_SIGNUP=1` to close registration. The app does not create an initial user or print credentials. Log in from **Shared Projects** in the Mac client using the same server address. Create a shared copy or open an existing project, and synchronize explicitly. Owners share with registered accounts as editors or readers. The browser synchronizes after edits and polls for remote changes when it has no local work or popup open.

**Use on This Device** opens local browser projects without an account or API service. They persist in IndexedDB, can be edited offline in an already loaded page, reopen after reload, and export as `.frontstage` files. Keep downloaded copies; clearing site/browser storage removes local projects. The browser test verifies that this workflow makes no API requests. To share a local project later, download it, sign in to the shared service and import it as a shared copy.

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

## Vercel browser deployment

The selected browser address is **https://frontstage-five.vercel.app/**, connected by the owner to `ratioprofile-design/frontstage/main`. The root `vercel.json` builds the static browser with `node scripts/build-web.mjs` and publishes `build/web`; it needs no npm dependencies. Keep the Vercel project's root at the repository root. Git pushes can trigger that connected deployment, but a successful source build does not establish its public deployment status.

The Swift/Vapor service requires a separate persistent container/VM host. Vercel's static deployment does not run it or store accounts/projects. Once a service host has an HTTPS address, configure:

- On Vercel: `FRONTSTAGE_API_ORIGIN` = the service's HTTPS origin, without `/api` or another path, then redeploy. This is a public address, not a secret. Alternatively enter it in **Shared server** on the sign-in form.
- On the Swift host: `FRONTSTAGE_WEB_ORIGIN=https://frontstage-five.vercel.app`, plus a private persistent `FRONTSTAGE_DATA_DIR`. This enables CORS only for the configured browser origin; bearer-token authorization and project permissions still apply.
- Enable `FRONTSTAGE_ALLOW_SIGNUP=1` only while enrolling accounts, then restart with signup disabled. Keep the service behind HTTPS and back up its persistent data.

An unset API origin lets the browser load but cannot supply accounts or sync on Vercel. No backend host has been provisioned yet. The owner's Apple signing configuration will be supplied separately in the release environment.

The public browser build was verified in [deployment run 39443862570](https://github.com/ratioprofile-design/frontstage/actions/runs/39443862570): root HTML, JavaScript and CSS matched this repository's build. Later deployments have their own Browser deployment workflow results. This verifies static delivery, not a hosted shared service.

For the static/browser split test, run `node scripts/build-web.mjs`, then `FRONTSTAGE_STATIC_BROWSER=1 node Server/Tests/browser-smoke.mjs` with Playwright installed. It serves the actual static build and talks to a separately started Swift service with CORS enabled. Same-origin and cross-origin flows are both covered; public HTTPS deployment is a separate acceptance gate.
