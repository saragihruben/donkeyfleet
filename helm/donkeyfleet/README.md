# DonkeyFleet Helm chart

Deploys DonkeyFleet — the SnapMirror replication controller — plus, optionally, a bundled
Postgres. **No ingress controller is bundled or required**; expose the app however your cluster
does (or not at all).

## Prerequisites

- Kubernetes ≥ 1.25, Helm ≥ 3.8 (OCI support).
- A `StorageClass` if you use the bundled Postgres (`postgres.enabled=true`, the default).
- A Secret with `db-username`, `db-password`, `oidc-client-secret` — either pre-created, synced
  by External Secrets Operator, or created by this chart (see [Secrets](#secrets)).
- Keycloak (or another OIDC provider) and, for cluster-credential reads, Vault.
- The target **namespace must already exist** — the chart does not create one. `helm install
  --create-namespace` makes it; with Flux/GitOps create it via `spec.install.createNamespace: true`,
  a `Namespace` in your kustomization, or by hand (`kubectl create ns donkeyfleet`).

## Install

```bash
helm install donkeyfleet . \
  -n donkeyfleet --create-namespace \
  -f my-values.yaml
```

A minimal `my-values.yaml`:

```yaml
image:
  repository: harbor.example.com/donkeyfleet/donkeyfleet
  tag: "1.0.0"
imagePullSecrets:
  - name: harbor-pull

config:
  oidc:
    issuer: https://keycloak.example.com/realms/donkeyfleet
    clientId: donkeyfleet
  vault:
    address: https://vault.example.com/
    kubernetes:
      role: kubernetes-donkeyfleet

secret:
  existingSecret: donkeyfleet-secrets   # you provide this Secret in the namespace

postgres:
  storageClass: fast-ssd
```

No ingress is created, so port-forward to try it:

```bash
kubectl -n donkeyfleet port-forward svc/donkeyfleet 8080:8080
```

### Existing `snapmirror-controller` releases

The public chart identity is `donkeyfleet`. If you switch an existing release from the former
`snapmirror-controller` chart, preserve its Kubernetes resource and Vault-bound ServiceAccount
names during the transition:

```yaml
fullnameOverride: snapmirror-controller
```

Without that override, the renamed chart intentionally renders new `donkeyfleet` resource names.
Update the Vault role bindings only if you also intend to adopt the new ServiceAccount name.

## Publishing the chart — private ("our" repo) and public

The chart ships as an **OCI artifact** (Helm ≥ 3.8), so the exact same `helm push` /
`helm install oci://…` commands work for any registry. Between your private repo and a public
one, only three things change: the registry URL, whether a login is needed to *pull*, and
whether an `imagePullSecret` is needed for the **image** (see the note at the end).

Package once, either way:

```bash
helm lint .
helm package .            # -> donkeyfleet-1.0.0.tgz
```

### Private — Harbor ("our" repo)

```bash
helm registry login harbor.example.com
helm push donkeyfleet-1.0.0.tgz oci://harbor.example.com/<project>/charts
```

Install (a robot account / login is needed to pull the chart, and a pull secret for the private image):

```bash
helm install donkeyfleet oci://harbor.example.com/<project>/charts/donkeyfleet \
  --version 1.0.0 -n donkeyfleet --create-namespace -f my-values.yaml
```

### Public — public OCI registry (Docker Hub or GHCR)

Create the repository as **public** first, then push. On Docker Hub the chart is an OCI artifact
under your namespace:

```bash
helm registry login registry-1.docker.io -u <your-user>
helm push donkeyfleet-1.0.0.tgz oci://registry-1.docker.io/<your-user>
```

Install straight from the public repo — **no `helm registry login` and no chart pull secret needed**:

```bash
helm install donkeyfleet oci://registry-1.docker.io/<your-user>/donkeyfleet \
  --version 1.0.0 -n donkeyfleet --create-namespace -f my-values.yaml
```

Verify the public artifact before announcing it:

```bash
helm show chart oci://registry-1.docker.io/<your-user>/donkeyfleet --version 1.0.0
helm pull oci://registry-1.docker.io/<your-user>/donkeyfleet --version 1.0.0
```

> **The chart is not the image.** Publishing the chart publicly does *not* publish the DonkeyFleet
> image — the chart still installs whatever `image.repository` points at. For your own test, keep
> `image` + `imagePullSecrets` set to your private image and it pulls fine. For anyone else to run
> the public chart, either point `image.repository` at a **public** image or have them set their
> own; otherwise the pod can't pull the image even though the chart installed.

> **Prefer a browsable `helm repo add`?** A classic GitHub Pages Helm repo is the alternative to
> public OCI: publish `index.yaml` + the `.tgz` to a `gh-pages` branch, then
> `helm repo add donkeyfleet https://<you>.github.io/<repo>`. Ask if you want that wired up
> instead of (or alongside) public OCI.

## Secrets

Pick one:

| Mode | Values | Notes |
|------|--------|-------|
| Reference existing | `secret.create=false`, `secret.existingSecret=<name>` | Default. You (or your platform) provide the Secret. |
| External Secrets Operator | `secret.externalSecret.enabled=true` + `secret.remoteKey`/`secretStoreRef` | Requires the `external-secrets.io` CRDs. Syncs from Vault. |
| Chart-managed | `secret.create=true` + `dbUsername`/`dbPassword`/`oidcClientSecret` | Convenient for dev; keeps creds in values — avoid in production. |

## Vault Kubernetes auth

DonkeyFleet reads ONTAP cluster credentials from Vault (M1+) via Vault's Kubernetes auth method.
Two ServiceAccounts, two jobs:

- **App SA** (the chart's fullname, e.g. `donkeyfleet`) — the identity the app **logs in
  as**. Your Vault role's `bound_service_account_names` must include this SA.
- **Reviewer SA** (`vaultKubernetesAuth.serviceAccountName`, default `<release>-vault-auth`) —
  holds `system:auth-delegator` so Vault can validate logins (`token_reviewer_jwt`). Set it to the
  reviewer SA your Vault method already uses (e.g. `vault-auth`) so no Vault-side change is needed,
  and treat it as stable infra — if you recreate it, refresh Vault's `token_reviewer_jwt`.

**Token review mode — which SA needs `auth-delegator`.** Run `vault read auth/<mount>/config`:

- **Static reviewer** (`token_reviewer_jwt_set=true`): Vault reviews every login with a dedicated
  reviewer SA, so only the **reviewer** SA needs `auth-delegator` (the chart's default wiring). The
  app SA needs no cluster privilege.
- **Client review** (`token_reviewer_jwt_set=false` and `disable_local_ca_jwt=true`): Vault reviews
  the login token with **that token itself**, so the **app** SA must be able to create
  TokenReviews. Set **`vaultKubernetesAuth.appAuthDelegator: true`** — the chart then binds the app
  SA to `system:auth-delegator`. Without it, a valid, bound token still gets `permission denied`.

By default the app authenticates with its **projected** ServiceAccount token (short-lived). If your
Vault auth method validates **legacy** tokens instead (`iss: kubernetes/serviceaccount`, no
audience), give the app SA a legacy token:

```yaml
vaultKubernetesAuth:
  legacyToken:
    enabled: true                 # creates <fullname>-token, mounts it, sets the Vault JWT path
    mountPath: /var/run/secrets/vault-auth
```

This makes the app log in with its **own** legacy token — not the reviewer's. (The modern
alternative is to accept projected tokens on the Vault side: `disable_iss_validation=true`.)
Set `vaultKubernetesAuth.enabled: false` if Vault is unused or you authenticate another way.

## Database (bundled or external)

The chart ships **DonkeyFleet itself**; the bundled Postgres is an **optional convenience**, not a
dependency welded into the app. Choose per environment:

| | Bundled (`postgres.enabled: true`, default) | External (`postgres.enabled: false`) |
|---|---|---|
| Use for | demos, evaluation, small single-pair footprints | production, or anywhere you run managed/HA Postgres |
| Chart creates | Postgres StatefulSet + PVC + Service | nothing — just DonkeyFleet |
| DB endpoint | computed from the bundled Service | your `config.database.url` |
| Backups / HA / upgrades | your problem, in-cluster | handled by your managed database |

**For production, external is the clean path** — the chart then renders only the application, and
Postgres is managed independently, as a stateful component generally should be. The app reads
`config.database.url`, so nothing in the code changes:

```yaml
# Bundled (default) — needs a StorageClass
postgres:
  enabled: true
  storageClass: fast-ssd
  storageSize: 50Gi

# External / managed (RDS, Cloud SQL, Aurora, your own Postgres)
postgres:
  enabled: false            # drops the PVC, StatefulSet and Postgres Service
config:
  database:
    url: "jdbc:postgresql://pg.example.com:5432/snapmirror"
```

With `postgres.enabled=false` the chart renders no Postgres objects at all. Either way the DB
credentials come from the Secret (`db-username` / `db-password`) — via `existingSecret`, ESO, or
chart-managed (see [Secrets](#secrets)). For a managed DB, put its username/password in that Secret.

For an external database: create the `snapmirror` database and a user with **DDL rights** (Flyway
runs the schema migrations at startup), and add `?sslmode=require` to the URL for TLS. Note that
flipping `postgres.enabled` from true to false does **not** migrate data — `pg_dump`/`pg_restore`
from the bundled Postgres first if you've already registered clusters, or start fresh (Flyway
rebuilds the schema, empty).

## Ingress

Off by default. Enable one shape:

```yaml
# Standard Ingress
ingress:
  enabled: true
  kind: ingress
  host: donkeyfleet.example.com
  ingressClassName: nginx
  tls:
    - hosts: [donkeyfleet.example.com]
      secretName: donkeyfleet-tls
```

```yaml
# Gateway API HTTPRoute (bring your own Gateway — Traefik, Istio, Cilium, …)
ingress:
  enabled: true
  kind: httproute
  host: donkeyfleet.example.com
  gateway:
    name: my-gateway
    namespace: gateway-system
    sectionName: https
    redirectToHttps: true
```

When enabled, `config.proxy.forwarding` (default true) makes OIDC build the right `redirect_uri`
behind the proxy — leave it on behind any ingress that terminates TLS.

## Other knobs

| Value | Default | Purpose |
|-------|---------|---------|
| `postgres.enabled` | `true` | Bundle Postgres. Set false + `config.database.url` for an external DB. |
| `vaultKubernetesAuth.enabled` | `true` | Create the SA + auth-delegator binding Vault's Kubernetes auth needs. |
| `config.reconcile.interval` | `5m` | Normal full discovery and long-running baseline observation cadence. |
| `config.reconcile.provisioningPollInterval` | `15s` | Safe follow-up cadence for active persisted provisioning steps and ONTAP jobs. |
| `config.reconcile.dryRun` | `true` | Safety: writes nothing to clusters while true. |
| `config.reconcile.dryRunUiOverride` | `false` | Keep the one-way kill switch in production. |
| `nodeSelector` / `tolerations` / `affinity` | `{}` | Scheduling (replaces the old hardcoded node). |
| `fullnameOverride` | `""` | Set to `snapmirror-controller` to keep the pre-chart resource names. |
| `replicaCount` | `1` | App replicas. >1 for UI availability only — reconcile stays single-writer. |
| `updateStrategy.type` | `Recreate` | `RollingUpdate` for zero-downtime multi-replica (needs backward-compatible migrations). |
| `podDisruptionBudget.enabled` | `false` | Keep a pod during node drains (multi-replica). |

The two reconcile intervals serve different purposes. An approval requests an immediate reconcile;
while destination-volume creation, relationship creation, or an ONTAP job is active, the controller
queues another full Observe/Apply pass after `provisioningPollInterval`. It never reissues an
unresolved job. Once initialization enters long-running baseline monitoring, it returns to the
normal `interval`. For example:

```yaml
config:
  reconcile:
    interval: 5m
    provisioningPollInterval: 15s
```

Keep `provisioningPollInterval` long enough for the ONTAP management API and full inventory read;
lowering it does not increase `max_concurrent_initializes` or bypass the intercluster bandwidth
budget.

## Replicas and availability

`replicaCount` defaults to **1**. The reconcile loop is **single-writer** — serialized by a
PostgreSQL advisory lock (`config.reconcile.lockKey`) — so extra pods never double-write; only the
one holding the lock reconciles at a time. Additional replicas are purely for **web-UI
availability**.

**No sticky sessions needed** — but know *why*, so a reconfiguration doesn't quietly cost you it.
DonkeyFleet keeps no server-side session. It's a confidential OIDC client: the authorization-code
session (ID/access tokens) rides in the encrypted `q_session` cookie, the login handshake's
state/nonce/return-path ride in the encrypted `q_auth` cookie, and CSRF is a double-submit cookie.
Each of those cookies is encrypted with a key **derived from the OIDC client secret**, which is
identical on every pod — so any pod decrypts any other pod's cookies, and even a login that
redirects via pod A and calls back on pod B just works. No ingress session affinity. (This holds
for a confidential client with a shared secret, which is how the chart ships; a public/PKCE-only or
JWT-auth client changes the key source — set the explicit key below and it holds regardless.)

Two things to set when `replicaCount > 1`:

- **`updateStrategy`** — the default `Recreate` restarts all pods together (brief downtime, but two
  app versions never overlap). Use `RollingUpdate` for zero-downtime rollouts **only if your
  migrations are backward-compatible** (old and new pods briefly share one schema):
  ```yaml
  replicaCount: 2
  updateStrategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 0, maxSurge: 1 }
  podDisruptionBudget:
    enabled: true
    minAvailable: 1
  ```
- **`config.oidc.sessionEncryptionSecretKey`** — **recommended for multi-replica.** Cookies already
  interoperate across pods without it (the key derives from the shared client secret), so it isn't
  required for correctness today — but set it anyway, for two reasons. First, it decouples session
  validity from the client secret: with the *derived* key, **rotating the OIDC client secret makes
  every live cookie undecryptable and logs all users out** — an explicit, stable key avoids that.
  Second, it removes the implicit dependency on secret-derivation: if the app is ever reconfigured so
  no usable client secret is present, Quarkus falls back to a **random per-pod key, which only works
  with a single replica**. Point it at a `>=32`-char value in your Secret:
  ```yaml
  config:
    oidc:
      sessionEncryptionSecretKey: oidc-encryption-secret   # a key in your Secret / ESO
  ```

The bundled Postgres stays single-replica regardless — `replicaCount` only affects the app.

## Upgrades

The Deployment uses `strategy: Recreate` (single-writer controller; Flyway runs at startup, so two
pods must never overlap). A release therefore incurs a few seconds of downtime. The
`checksum/config` annotation rolls the pod automatically when the ConfigMap changes.
