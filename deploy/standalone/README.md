# DonkeyFleet — standalone stack (Docker Desktop)

Runs the whole system on one machine, no Kubernetes: **Postgres + Vault + Keycloak +
DonkeyFleet**. Built for demo boxes and small footprints — for a production fleet, run the
Kubernetes deployment instead. See [Scope](#scope-standalone-vs-kubernetes).

## Scope: standalone vs Kubernetes

Standalone is for **demo boxes and small footprints**. It is usable in production, but only at
that scale — think a **single SVM pair with no more than ~10 volumes**. The bundled Vault and
Keycloak run in dev mode (in-memory, fixed credentials), so they are not a hardened control plane.

For a **real production fleet**, run DonkeyFleet on **Kubernetes** (the Helm chart) backed by
external, persistent services:

| Concern  | Standalone (this stack)           | Production (Kubernetes)                    |
|----------|-----------------------------------|--------------------------------------------|
| Secrets  | Vault dev mode, one root token    | External Vault + External Secrets Operator |
| Identity | Keycloak dev mode, imported realm | Managed Keycloak / your OIDC provider      |
| Database | Bundled Postgres, one volume      | Managed or HA PostgreSQL                   |
| Scale    | 1 SVM pair, ≤ ~10 volumes         | Many pairs and relationships               |

DonkeyFleet is deliberately a **narrow, volume-level SnapMirror controller** — an auditable
drift-detect-and-correct loop, not a general data-management platform. For broad, multi-service
NetApp management, NetApp **BlueXP** (or comparable tooling) is likely the better fit; DonkeyFleet's
value is the focused, human-gated control loop over exactly what it manages.

## How this distribution runs

This public deployment package uses pull mode: Compose pulls the image selected by
`DONKEYFLEET_IMAGE`. It does not contain the DonkeyFleet source or a source-build override.

## Prerequisites

- Docker Desktop (provides `host.docker.internal`, which this stack relies on).
- Free ports **8090** (app), **8081** (Keycloak), **8200** (Vault), **5432** (Postgres).
- The ability to pull the image configured by `DONKEYFLEET_IMAGE`.

## Run it

Copy `.env.example` to `.env`, set `DONKEYFLEET_IMAGE` to an image you can pull, then run:

```bash
docker compose -f docker-compose.yml up -d
```

Then open **http://host.docker.internal:8090** and sign in:

| User | Password | Roles |
|------|----------|-------|
| `donkey` | `donkey` | read, approve, administer |
| `reader` | `reader` | read |

Keycloak admin console: http://host.docker.internal:8081 — `admin` / `admin`.

## Reconcile and Apply defaults

The standalone runtime values are:

| Setting | Default | Purpose |
|---------|---------|---------|
| `RECONCILE_INTERVAL` | `5m` | Full discovery and long-running baseline monitoring |
| `PROVISIONING_POLL_INTERVAL` | `15s` | Safe follow-up while volume and relationship jobs are active |
| `RECONCILE_DRY_RUN` | `true` | Starts the stack without destination writes |
| `RECONCILE_DRY_RUN_UI_OVERRIDE` | `true` | Lets an administrator use the audited Dry Run / Apply Live control |

The 15-second follow-up does not blindly retry ONTAP. Each run acquires the PostgreSQL advisory
lock, observes current state, and resumes only from the persisted provisioning checkpoint. Once
initialization starts, baseline monitoring returns to the normal five-minute cadence.

`max_actions_per_run`, `max_concurrent_initializes`, and the bandwidth budget remain automation
profile settings. They are intentionally not deployment environment variables.

The standalone stack starts in Dry Run. Because its UI override is deliberately unlocked, an
administrator can select Apply Live without changing `.env`. That choice is stored in PostgreSQL
and survives an app-container restart. Set `RECONCILE_DRY_RUN_UI_OVERRIDE=false` for a locked
deployment where Apply cannot be enabled from the UI.

## Publishing the image (so others can pull, without your source)

Build the image and push it to a registry your recipients can reach. From the **repo root**
(where the `Dockerfile` is):

```bash
docker build -t <your-dockerhub-user>/donkeyfleet:1.0.0 .
```

```bash
docker login
```

```bash
docker push <your-dockerhub-user>/donkeyfleet:1.0.0
```

Recipients then set `DONKEYFLEET_IMAGE=<your-dockerhub-user>/donkeyfleet:1.0.0` and run
`docker compose up`.

> **Before you push to a *public* repo, know this:** the image is **JVM bytecode**, which
> decompiles back to near-source with standard tools — a public image effectively shares your
> logic. If that matters:
> - **Private repo** (Docker Hub private, GHCR private, or your Harbor) + give recipients pull
>   credentials — not public, but they need creds and network to your registry; or
> - **GraalVM native image** — a compiled binary that resists decompilation (and starts faster).
>   It's already this project's stated target; build it from `src/main/docker/Dockerfile.native`.
>
> A public JVM image is fine if "no source" just means "recipients shouldn't have to clone and
> build" rather than hard IP protection.

### Distributing via a private Docker Hub repo

A private repo keeps the image access-controlled without native-image complexity — the JVM
bytecode is only reachable by people you grant pull access.

1. **Create the repository as _private_ first** in the Docker Hub UI (Repositories → Create →
   Visibility: Private). A plain `docker push` to a new name creates it **public** by default, so
   creating it private up front avoids a public window.
2. Build, `docker login`, and push as above.
3. Grant pull access — add recipients as collaborators on the repo, or share a **read-only
   access token** (Docker Hub → Account settings → Personal access tokens).

Recipients authenticate once before pulling:

```bash
docker login -u <your-dockerhub-user>
```

then set `DONKEYFLEET_IMAGE=<your-dockerhub-user>/donkeyfleet:1.0.0` and run `docker compose up`.
(The Helm chart's `imagePullSecrets` is the Kubernetes equivalent of that login.)

## What to put in the distribution bundle

Zip these and hand them over — **not** the source, **not** the override:

```
docker-compose.yml
keycloak/realm-export.json
.env            # with DONKEYFLEET_IMAGE set to your published ref
README.md       # (this file, or a trimmed copy)
```

Omit `docker-compose.override.yml` (that's the source-build path) and everything under `../..`.

**Or run the helper**, which stages exactly those files (with `.env` copied from `.env.example`)
and zips them to `dist/donkeyfleet-standalone.zip`:

```bash
./make-bundle.sh                                            # macOS / Linux
```

```powershell
powershell -ExecutionPolicy Bypass -File make-bundle.ps1   # Windows
```

## Deploy on another machine (pull mode)

The target machine needs only three things — `docker-compose.yml`, the `keycloak/` folder, and a
`.env` — plus pull access to the image. It does **not** need the source or
`docker-compose.override.yml` (that file forces a build from `../..`, which isn't present here).

1. Copy `docker-compose.yml`, `keycloak/`, and `.env.example` across (leave the override behind).
2. Create the env file — `docker-compose.yml` reads `.env`, **not** `.env.example`, and this is
   where `DONKEYFLEET_IMAGE` comes from:
   ```bash
   cp .env.example .env
   ```
3. Authenticate so the private image can be pulled:
   ```bash
   docker login
   ```
4. Start the stack — the explicit `-f` stops a stray override from being auto-merged:
   ```bash
   docker compose -f docker-compose.yml up -d
   ```
5. Open **http://host.docker.internal:8090** and sign in as `donkey` / `donkey`.

**Plain Linux host (no Docker Desktop):** the containers resolve `host.docker.internal` through the
compose `extra_hosts`, but the browser on the host does not. Add it once:

```bash
echo "127.0.0.1 host.docker.internal" | sudo tee -a /etc/hosts
```

Browsing from a different machine? Put the same line (pointing at the server's IP) on that client,
or front the stack with a real hostname and set `OIDC_ISSUER` / `KC_HOSTNAME` to match.

## Why `host.docker.internal` and not `localhost`

OIDC only works if the browser and the app agree on the token issuer. The browser reaches
Keycloak from your host; the app reaches it from inside a container — `localhost` means two
different things to them. `host.docker.internal` resolves to the host from **both** on Docker
Desktop, so the `iss` claim matches (`http://host.docker.internal:8081/realms/donkeyfleet`).
Always open the app at `http://host.docker.internal:8090`.

## Services and persistence

| Service | Port (host) | Persists across restart? |
|---------|-------------|--------------------------|
| `donkeyfleet` | 8090 → 8080 | stateless |
| `keycloak` | 8081 → 8080 | realm re-imported each fresh start |
| `vault` | 8200 | **No** — dev mode is in-memory; re-seed after any restart |
| `postgres` | 5432 | **Yes** — named volume `pgdata` (only `down -v` wipes it) |

Your DonkeyFleet data (clusters, policies, relationships) lives in Postgres and survives
restarts. Vault runs in dev mode (in-memory), so seeded cluster credentials are lost on any Vault
restart — re-`vault kv put` them (a durable Vault means switching off dev mode).

## Upgrade the application

Use a new immutable image tag in `.env`, then pull and recreate the app container while retaining
the `pgdata` volume:

```bash
docker compose -f docker-compose.yml pull donkeyfleet
docker compose -f docker-compose.yml up -d donkeyfleet
```

Flyway applies pending database migrations when the new app starts. The current migrations resume
plans rejected by the obsolete SnapMirror `type` argument, repair completed baselines that were
incorrectly suspended, and dismiss premature baseline-overrun notifications created from estimates
shorter than the new 10-minute operational floor. Do not run `docker compose down -v` during an
upgrade; that command deletes the durable PostgreSQL state required for crash recovery.

## Vault: seed a cluster credential

The app reads ONTAP credentials from Vault at the cluster's **Vault path** (KV v2 under `secret/`,
keys `username`/`password`). Seed one:

```bash
docker compose exec vault sh -c "VAULT_TOKEN=donkeyfleet-root vault kv put secret/snapmirror/clusters/onprem1 username='ONTAP_USER' password='ONTAP_PASS'"
```

Then register the cluster in the UI with **Vault path** = `snapmirror/clusters/onprem1`. (A live
ONTAP/FSx endpoint reachable from the container is also required — registration probes it.)

## Teardown

```bash
docker compose down
```

```bash
docker compose down -v
```

`down` keeps the Postgres volume; `down -v` wipes it (fresh DB + re-imported realm next time).

## Troubleshooting

- **Login bounces / "invalid issuer"** — you opened `localhost:8090` instead of
  `host.docker.internal:8090`.
- **`host.docker.internal` doesn't resolve in the browser (Linux host)** — plain Docker Engine
  doesn't add it to the host. Add `127.0.0.1 host.docker.internal` to `/etc/hosts`; see
  [Deploy on another machine](#deploy-on-another-machine-pull-mode).
- **`pull access denied` / `manifest unknown`** — `DONKEYFLEET_IMAGE` isn't set to a ref you can
  pull (recipient mode), or the image isn't pushed yet.
- **First request 401 / OIDC not ready** — Keycloak takes ~30–60s to import the realm on first
  boot; the app retries. Wait and reload.
- **`ERROR … OIDC Server is not available` at startup** — expected boot race; it recovers.
