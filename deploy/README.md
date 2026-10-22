# Persistent shared-service deployment

This is deployment configuration, not an existing hosted service. The browser is hosted separately at https://frontstage-five.vercel.app/. A Linux host with Docker Compose, persistent disk, a backend hostname pointing at it, and inbound ports 80/443 is required. No host/account has been selected yet.

From the repository root on that host:

```sh
export FRONTSTAGE_SERVICE_DOMAIN=your-backend-hostname
export FRONTSTAGE_ALLOW_SIGNUP=1
docker compose -f deploy/compose.yaml up -d --build
curl --fail "https://$FRONTSTAGE_SERVICE_DOMAIN/health"
```

Caddy obtains HTTPS certificates for that hostname. The server is reachable through the proxy, with only the proxy ports published. Its project store and certificates use named persistent volumes. Run only one server process against the project volume.

Set Vercel's `FRONTSTAGE_API_ORIGIN` to `https://your-backend-hostname` and redeploy. Create the intended accounts, then disable new enrollment:

```sh
export FRONTSTAGE_ALLOW_SIGNUP=0
docker compose -f deploy/compose.yaml up -d server
```

Acceptance before production: create accounts on the deployed HTTPS endpoint; share one project between two browser/Mac sessions; test reader rejection, simultaneous snippet edits, a genuine text conflict and reconnect; restart the container and confirm data persists. Local automated tests do not substitute for these deployed checks. Rate limiting, account recovery, operational monitoring and a production review remain open.

## Backup and restore

Backups contain private projects and password hashes. Keep them outside the repository on private encrypted storage, with retention appropriate to the owner. The backup utility validates the versioned store envelope, refuses to overwrite a destination and creates mode-0600 files. It is not a full semantic database validator. Stop the service before either operation.

```sh
docker compose -f deploy/compose.yaml stop server
docker compose -f deploy/compose.yaml cp server:/data/frontstage-server.json /private/path/source-store.json
python3 scripts/server-backup.py backup /private/path/source-store.json /private/path/new-backup.json --server-stopped
docker compose -f deploy/compose.yaml start server
```

Test restoration on a separate deployment/volume first. Preserve the existing store as a separate backup before replacing it. Restoring clears sessions so a backup cannot revive revoked logins.

```sh
docker compose -f deploy/compose.yaml stop server
python3 scripts/server-backup.py restore /private/path/new-backup.json /private/path/restored-store.json --server-stopped
docker compose -f deploy/compose.yaml cp /private/path/restored-store.json server:/data/frontstage-server.json
docker compose -f deploy/compose.yaml run --rm --user 0 --entrypoint chown server 10001:10001 /data/frontstage-server.json
docker compose -f deploy/compose.yaml start server
```

Verify sign-in, membership and project revisions after restore. Removing Docker volumes destroys the stored data; ordinary container recreation retains them.
