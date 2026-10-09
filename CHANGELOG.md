# Changelog

All notable changes to the public DonkeyFleet deployment assets are recorded here.

## 1.1.2 — 2026-10-09

- Bumps the default application version (`appVersion`) and image tag to `1.3.1`, picking up the 1.3.1
  application release: per-SVM-pair scope filters, the "Protection established" notification, and the
  Netty, Jackson, and base-image security fixes.

## 1.1.1 — 2026-09-22

- Lowers the default container memory limit from `768Mi` to `640Mi` (requests unchanged at `512Mi`);
  the heap stays capped near `320Mi` through `jvm.maxRamPercentage: 50`, trimming the footprint while
  keeping ample non-heap headroom.

## 1.1.0 — 2026-09-21

- Fixes pods being OOMKilled at the default memory limit. Adds a `jvm.maxRamPercentage` value
  (default `50`, rendered as `-XX:MaxRAMPercentage=50`) so the heap leaves room for non-heap memory,
  and raises the default container memory to a `768Mi` limit / `512Mi` request.
- Adds an `extraEnv` passthrough for arbitrary container environment variables (for example JVM flags
  via `JAVA_OPTS_APPEND`).
- Bumps the default application version (`appVersion`) to `1.3.0`.

## 1.0.1 — 2026-08-23

- Moves the Helm OCI artifact to the dedicated `donkeyfleet-chart` repository.
- Renames the chart artifact to `donkeyfleet-chart` while defaulting `nameOverride` to
  `donkeyfleet`, preserving the Kubernetes resource names rendered by release `donkeyfleet`.
- Keeps the application image independently versioned in the `donkeyfleet` repository.

## 1.0.0 — 2026-08-23

First stable public Helm chart release.

- Deploys DonkeyFleet with configurable image, resources, scheduling, ingress, and security context.
- Supports bundled or external PostgreSQL.
- Supports existing Kubernetes Secrets, chart-managed Secrets, and External Secrets Operator.
- Includes Vault Kubernetes-auth wiring for static-reviewer and client-review configurations.
- Supports multiple application replicas with a PodDisruptionBudget and configurable update strategy.
- Exposes normal reconciliation and fast, checkpoint-safe provisioning follow-up intervals.
- Includes standalone Docker Compose deployment assets for evaluation and small installations.

## 0.3.1 — 2026-08-21

Initial public preview release. It remains available for reproducible existing installations.
