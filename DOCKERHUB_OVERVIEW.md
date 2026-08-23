# DonkeyFleet

DonkeyFleet is a lightweight, volume-level SnapMirror controller for protecting data from
on-premises NetApp ONTAP to Amazon FSx for NetApp ONTAP. It discovers source volumes, evaluates
automation policy, asks an operator to approve new protection, and drives destination volume,
SnapMirror relationship, and baseline initialization through crash-recoverable checkpoints.

It is intentionally narrower than a general storage-management platform: DonkeyFleet provides an
auditable drift-detect-and-correct loop for the relationships placed under its control.

## Core guarantees

- Source clusters are always read-only.
- Volume UUID is the identity; names are display data.
- Dry-run is the safe default.
- Approval records intent but does not call ONTAP from the web request.
- Provisioning intent and ONTAP job UUIDs are persisted in PostgreSQL.
- Unresolved ONTAP jobs are observed, never blindly retried.
- Baseline concurrency and bandwidth are controlled by automation profiles.
- Destructive cleanup always requires human confirmation.

## Deployment options

| Option | Intended use | Requirements |
|---|---|---|
| Standalone Docker Compose | Evaluation, demonstrations, and small deployments | Docker Desktop or Docker Engine; a DonkeyFleet image |
| Helm chart | Kubernetes and production deployments | Kubernetes 1.25+, Helm 3.8+, OIDC, Vault, and PostgreSQL or the optional bundled database |

## Install with Helm

The public chart is an OCI artifact:

```bash
helm show chart oci://registry-1.docker.io/saragihruben29/donkeyfleet --version 0.3.1
```

Create `my-values.yaml`:

```yaml
image:
  repository: registry.example.com/donkeyfleet/donkeyfleet
  tag: "1.0.0"
imagePullSecrets:
  - name: registry-pull

config:
  oidc:
    issuer: https://identity.example.com/realms/donkeyfleet
    clientId: donkeyfleet
    sessionEncryptionSecretKey: oidc-encryption-secret
  vault:
    address: https://vault.example.com/
    kubernetes:
      role: kubernetes-donkeyfleet
      authMountPath: kubernetes-donkeyfleet
  reconcile:
    interval: 5m
    provisioningPollInterval: 15s
    dryRun: true
    dryRunUiOverride: false

secret:
  existingSecret: donkeyfleet-secrets

postgres:
  enabled: false
```

The referenced Secret must contain `db-username`, `db-password`, and `oidc-client-secret`. When
`sessionEncryptionSecretKey` is set, it must also contain that named key with at least 32
characters.

Install:

```bash
helm install donkeyfleet \
  oci://registry-1.docker.io/saragihruben29/donkeyfleet \
  --version 0.3.1 \
  --namespace donkeyfleet \
  --create-namespace \
  --values my-values.yaml
```

The chart is public, but it does not make the application image public. Configure an image your
cluster can pull.

## External PostgreSQL

Production deployments should normally use an independently operated PostgreSQL service:

```yaml
postgres:
  enabled: false

config:
  database:
    url: jdbc:postgresql://postgres.example.com:5432/donkeyfleet?sslmode=require
```

The database user needs DDL rights because Flyway applies migrations at startup. PostgreSQL is
part of DonkeyFleet's recovery model: approvals, provisioning checkpoints, ONTAP job UUIDs, and
the reconcile advisory lock depend on durable database state.

For evaluation, leave `postgres.enabled: true` and choose a suitable StorageClass.

## High availability

Multiple replicas improve web availability while reconciliation remains single-writer through a
PostgreSQL advisory lock. No ingress affinity is required. For stable sessions across replicas and
OIDC client-secret rotation, configure one shared `sessionEncryptionSecretKey`, use a
PodDisruptionBudget, and use `RollingUpdate` only with backward-compatible database migrations.

## Standalone installation

Download or clone the deployment assets, enter `deploy/standalone`, copy `.env.example` to `.env`,
and set `DONKEYFLEET_IMAGE`:

```bash
cp .env.example .env
docker compose -f docker-compose.yml up -d
```

Open `http://host.docker.internal:8090`. The stack includes PostgreSQL, development-mode Vault,
and development-mode Keycloak. It is suitable for evaluation and small installations, not as a
hardened or highly available production control plane.

The standalone defaults are a five-minute full observation interval and a 15-second safe
provisioning follow-up. The fast follow-up observes persisted checkpoints; it does not bypass
identity validation, concurrency limits, or unresolved-job protection.

## Documentation

The complete deployment examples and operational notes are available in the public deployment
repository:

- `helm/donkeyfleet/README.md`
- `deploy/standalone/README.md`

