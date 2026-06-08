# Troubleshooting Guides

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

This directory holds the troubleshooting guides for the `udr` HSS/UDR: symptoms an operator observes in production and how to diagnose and resolve them. Each guide follows the project documentation standard (see the [manual README](../README.md)); each entry carries a stable identifier, names the observable symptom, lists likely causes most-probable first, gives a diagnosis with the expected and the failing observation for each cause, and states a normative resolution.

## How to use this section

Search by the **symptom you observe**, not by the cause you suspect. Each entry is titled by what the operator sees — a missing answer, an exact error string, an HTTP status, a log line — because at the start of an incident the cause is not yet known. Find the entry whose Symptom matches your observation, then work through its Diagnosis steps in order; each step distinguishes the cause it confirms from the others.

The entries do not repeat configuration detail or procedures. Where a resolution is a configuration change or an operational task, the entry links the relevant [configuration reference](../configuration/README.md) or [operations runbook](../operations/README.md) instead of restating it. Terms and abbreviations are defined once in the [glossary](../glossary.md).

> [!IMPORTANT]
> The default `udr_db` backend is in-memory [ETS](../glossary.md) and holds all subscriber data in the [BEAM](../glossary.md) node's memory only. Several symptoms below — a subscriber that "disappears" after a restart, or an `AIR`/`GET` that returns "unknown" for a subscriber provisioned before a restart — trace to this. The persistence model is stated once in the [operations README](../operations/README.md#persistence-model--read-this-first) and governed by the [data-store configuration reference](../configuration/data-store.md).

## Guides

| Guide | Covers symptoms on… | Entry IDs |
| --- | --- | --- |
| [S6a Diameter](s6a.md) | The S6a listener and the AIR/ULR/PUR/CLR procedures. | `TS-S6A-001` … `TS-S6A-005` |
| [SBI (Nudr-DR)](sbi.md) | The 5G Service-Based Interface data-repository listener. | `TS-SBI-001` … `TS-SBI-004` |
| [Provisioning API](provisioning.md) | The admin subscriber provisioning API. | `TS-PROV-001` … `TS-PROV-004` |
| [Data store](data-store.md) | The `udr_db` backend (ETS or MongoDB). | `TS-DB-001` … `TS-DB-003` |
| [Cluster](cluster.md) | Erlang distribution and per-IMSI session locking. | `TS-CLUSTER-001` … `TS-CLUSTER-002` |
| [Observability](observability.md) | OpenTelemetry spans and metrics export. | `TS-OBS-001` … `TS-OBS-002` |

## Conventions used in these guides

- Erlang-shell diagnostic commands are run at the node's console. Opening a console or a remote console on a deployed `prod`-mode release is covered in [`RUN-LIFECYCLE-001`](../operations/lifecycle.md).
- Shell commands (`ss`, `curl`, `epmd`) are run on the node's host unless stated otherwise.
- The shipped listener defaults are loopback-only: S6a on `127.0.0.1:3868`, [SBI](../glossary.md) on `127.0.0.1:8080`, provisioning on `127.0.0.1:8090`.
- HTTP status codes and Diameter result codes cited here are the ones confirmed in the [interface references](../interfaces/README.md); each entry links the relevant reference.
