# Operations Runbooks

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This directory holds the operational runbooks for the `udr` HSS/UDR: procedures an operator runs to deploy, run, provision, connect, observe, scale, upgrade, and protect the system. Each runbook follows the project documentation standard (see the [manual README](../README.md)); each procedure carries a stable identifier, states its pre-conditions before its steps, ends with an observable Verify, and gives a rollback or on-failure path.

This directory describes operational tasks only. The parameters those tasks set are defined in the [configuration references](../configuration/README.md); the interfaces they exercise are defined in the [interface references](../interfaces/README.md). Terms and abbreviations are defined once in the [glossary](../glossary.md).

## Persistence model — read this first

> [!IMPORTANT]
> The default `udr_db` backend is in-memory [ETS](../glossary.md). ETS holds all provisioned subscriber data in the [BEAM](../glossary.md) node's memory and discards it when the node stops. An ETS-backed node therefore has **no** persistence: a restart, a crash, or a backend switch loses every provisioned subscriber. Backup and restore are meaningful only with the [MongoDB](../glossary.md) backend, which stores data in an external database that survives a node restart. The runbooks below state, for each procedure, whether it depends on the MongoDB backend. Backend selection is governed by the [data-store configuration reference](../configuration/data-store.md).

## Runbooks

| Runbook | Procedures (IDs) |
| --- | --- |
| [Deploy a production release](deploy.md) | `RUN-DEPLOY-001` |
| [Node lifecycle: start, stop, restart, console](lifecycle.md) | `RUN-LIFECYCLE-001` |
| [Subscriber provisioning: create, read, delete, bulk](provisioning.md) | `RUN-PROVISION-001` |
| [Connect and verify an MME (S6a peer)](s6a-peer.md) | `RUN-S6A-PEER-001` |
| [Configure observability (OpenTelemetry / OTLP)](observability.md) | `RUN-OBSERVABILITY-001` |
| [Select and migrate the data backend (ETS ↔ MongoDB)](backend.md) | `RUN-BACKEND-001` |
| [Back up and restore (MongoDB backend)](backup-restore.md) | `RUN-BACKUP-001` |
| [Cluster: form, add a node, remove a node](cluster.md) | `RUN-CLUSTER-001` |
| [Upgrade to a new version](upgrade.md) | `RUN-UPGRADE-001` |
| [Manage secret material (Ki / OPc) safely](secrets.md) | `RUN-SECRETS-001` |

## Conventions used in these runbooks

- Commands shown for a `prod`-mode release use the path `_build/prod/rel/udr/bin/udr`. The release name is `udr` and its version is `0.1.0`, both set in the `relx` section of `rebar.config`.
- Commands shown for a development node use `rebar3 shell` or `_build/default/rel/udr/bin/udr`.
- HTTP examples use `curl`. Erlang-shell examples are run at the node's console (see [`RUN-LIFECYCLE-001`](lifecycle.md)).
- The shipped listener defaults are loopback-only: S6a on `127.0.0.1:3868`, [SBI](../glossary.md) on `127.0.0.1:8080`, provisioning on `127.0.0.1:8090`.
