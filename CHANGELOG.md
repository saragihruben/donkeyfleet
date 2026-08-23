# Changelog

All notable changes to the public DonkeyFleet deployment assets are recorded here.

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
