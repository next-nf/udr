# Troubleshooting: Data Store (`udr_db`, `udr_db_mongo`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers symptoms an operator observes around the `udr_db` data backend: a node that fails to start or whose data operations error because [MongoDB](../glossary.md) is unreachable, a backend that resolved to a different module than intended, and subscriber data that "disappears" after a restart because the in-memory [ETS](../glossary.md) backend does not persist. Backend selection and the MongoDB connection options are defined in the [data-store configuration reference](../configuration/data-store.md); switching backends is the procedure [`RUN-BACKEND-001`](../operations/backend.md).

> [!IMPORTANT]
> The default backend is in-memory ETS, which holds all subscriber data in the [BEAM](../glossary.md) node's memory only and discards it when the node stops. This single fact underlies several symptoms in this section and in the S6a, SBI, and provisioning guides. The persistence model is stated once in the [operations README](../operations/README.md#persistence-model--read-this-first).

---

## TS-DB-001: The node fails to start, or data operations error, because MongoDB is unreachable

### Symptom

With the MongoDB backend selected (`{backend, udr_db_mongo}`), one of two things is observed:

- the node does not finish booting — the boot log shows a crash originating in `udr_db_mongo_conn`, and the release control script's `ping` does not return `pong`; or
- the node is up but every read and write that reaches the backend errors. On the SBI a `PUT`/`DELETE` returns `500` "storage error" ([TS-SBI-003](sbi.md#ts-sbi-003-a-put-or-delete-on-amf-3gpp-access-returns-500-with-detail-storage-error)); on provisioning a `PUT` returns `500` "storage error" ([TS-PROV-003](provisioning.md#ts-prov-003-a-put-returns-500-storage-error)); on S6a an `AIR` that needs an SQN write can return `5012` ([TS-S6A-003](s6a.md#ts-s6a-003-an-air-is-answered-with-unable_to_comply-5012)).

### Affected component

`udr_db_mongo` — the connection owner (`udr_db_mongo_conn`) — and the MongoDB server.

### Likely causes

*(Ordered, most probable first.)*

1. The MongoDB server is not reachable at the configured `host` and `port` (it is down, on a different host/port, or blocked by the network). The connection owner connects at start; a failed connect crashes it.
2. MongoDB is reachable but rejects authentication — `login`, `password`, or `auth_source` is wrong, or the user lacks rights on the configured database.
3. The `backend` was set to `udr_db_mongo` but `backend_opts` does not point at the intended server, so the node connects to the wrong (or a non-existent) MongoDB.

### Diagnosis

1. Confirm the configured backend and connection options at the node's console (or, if the node will not boot, read them from `config/sys.config`):
   ```erlang
   {application:get_env(udr_db, backend), application:get_env(udr_db, backend_opts)}.
   ```
   - Expected for a MongoDB deployment: `{{ok, udr_db_mongo}, {ok, #{host := ..., port := ...}}}` pointing at the intended server.
   - If `backend_opts` names a wrong host or port, cause 3 applies.
2. Confirm the MongoDB server is reachable from the node's host:
   ```sh
   nc -vz <mongo-host> 27017
   ```
   - Expected: the connection succeeds.
   - If it fails, the server is unreachable — cause 1.
3. If the node is up, confirm the cached connection handle at the console:
   ```erlang
   catch is_pid(udr_db_mongo_conn:conn()).
   ```
   - Expected: `true`.
   - If it raises (the `persistent_term` is absent because the connection never established) or returns otherwise, the backend is not connected — cause 1 or cause 2.
4. If MongoDB is reachable (Step 2 succeeds) but the handle is still absent, inspect the MongoDB server log for an authentication or authorization rejection — cause 2.

### Resolution

*(Normative.)*

- For cause 1: the MongoDB server `shall` be reachable at the `host` and `port` in `backend_opts` before the node is started with the MongoDB backend. Once reachable, the node `shall` be restarted (the resolved backend and its connection are established at boot).
- For cause 2: `login`, `password`, and `auth_source` `shall` match a MongoDB user with read/write rights on the configured `database`, per the [data-store configuration reference §5.2](../configuration/data-store.md#52-backend_opts-for-mongodb).
- For cause 3: `backend_opts` `shall` name the intended MongoDB server.
- As an interim measure where persistence is not yet required, the node `may` be reverted to the ETS backend by setting `{backend, udr_db_ets}` and restarting, per the [backend runbook on-failure guidance](../operations/backend.md#rollback--on-failure). Reverting to ETS does not restore data held only in MongoDB.

> [!WARNING]
> The connection owner establishes the MongoDB connection at start and caches the handle. A backend that cannot connect at boot does not retry into a healthy state on its own; the node `shall` be restarted once MongoDB is reachable.

### Prevention

*(Informative.)* The [data-store configuration reference §7](../configuration/data-store.md#7-verify) and the [backend runbook Verify step](../operations/backend.md#verify) confirm both the resolved backend and a live connection (`is_pid(udr_db_mongo_conn:conn())`) before the node is put into service; running them after any backend or `backend_opts` change catches an unreachable database early.

### Related

- [Data-store configuration reference §5.2, §7](../configuration/data-store.md#52-backend_opts-for-mongodb) — MongoDB connection options.
- [`RUN-BACKEND-001`](../operations/backend.md) — select and migrate the backend.
- [TS-SBI-003](sbi.md#ts-sbi-003-a-put-or-delete-on-amf-3gpp-access-returns-500-with-detail-storage-error), [TS-PROV-003](provisioning.md#ts-prov-003-a-put-returns-500-storage-error), [TS-S6A-003](s6a.md#ts-s6a-003-an-air-is-answered-with-unable_to_comply-5012) — the operation-level symptoms an unreachable store produces.

---

## TS-DB-002: The running backend is not the one intended (ETS instead of MongoDB, or the reverse)

### Symptom

The node is healthy and serving requests, but its persistence behavior is wrong for the deployment: data does not survive a restart when MongoDB was intended, or the node tries to reach a MongoDB that was not intended. A check of the resolved backend returns a different module than configured.

### Affected component

`udr_db` — backend resolution.

### Likely causes

*(Ordered, most probable first.)*

1. The `config/sys.config` `udr_db` block was changed, but the node was not restarted. `udr_db` caches the resolved backend in a `persistent_term` on first use, so a `backend` change does not take effect until restart.
2. The change was made to a `config/sys.config` that the running release does not read (for example an edit under the source tree while the node runs a `prod`-mode release that bundled its own copy).
3. The `udr_db` block is absent or malformed, so the in-code default (`udr_db_ets`) applies instead of the intended MongoDB.

### Diagnosis

1. Compare the resolved backend against the configured one. At the node's console:
   ```erlang
   {udr_db:backend(), application:get_env(udr_db, backend)}.
   ```
   - Expected: both agree, for example `{udr_db_mongo, {ok, udr_db_mongo}}`.
   - If `udr_db:backend()` is `udr_db_ets` while `get_env` reports `{ok, udr_db_mongo}`, the resolved backend was cached before the change and the node was not restarted — cause 1.
   - If `get_env` reports `undefined`, the running node never loaded a `udr_db` `backend` key — cause 3 (the in-code default `udr_db_ets` then applies), or cause 2 (it read a different config).
2. Confirm which `config/sys.config` the running release uses. For a `prod`-mode release the active file is under the release directory, not the source tree.
   - Expected: the edited file is the one the running release loaded.
   - If the edit was made to a source-tree copy while a bundled release runs its own, cause 2 applies.

### Resolution

*(Normative.)*

- For cause 1: after changing `backend` in `config/sys.config`, the node `shall` be restarted, because the resolved backend is cached in a `persistent_term` (per the [data-store configuration reference §3](../configuration/data-store.md#3-where-configuration-lives) and [§5.1](../configuration/data-store.md#51-backend)).
- For cause 2: the change `shall` be applied to the `config/sys.config` the running release actually reads, then the node restarted.
- For cause 3: the `udr_db` block `shall` set `backend` to the intended module; an absent or malformed block leaves the in-code default `udr_db_ets` in effect.

### Prevention

*(Informative.)* Making `udr_db:backend()` the first Verify step after any backend change — as the [backend runbook](../operations/backend.md#verify) does — confirms the resolved module matches the intent before the node carries traffic.

### Related

- [Data-store configuration reference §3, §5.1](../configuration/data-store.md#3-where-configuration-lives) — the `persistent_term` cache and the restart requirement.
- [`RUN-BACKEND-001`](../operations/backend.md) — switch the backend.

---

## TS-DB-003: Provisioned data disappears after a node restart

### Symptom

Subscribers that were provisioned successfully (a `PUT` returned `201`) are gone after the node restarts: a provisioning `GET` returns `404` "subscriber not found", an SBI `GET` returns `404`, and an S6a `AIR` returns `5001` USER_UNKNOWN — for subscribers that were present before the restart.

### Affected component

`udr_db` with the ETS backend (`udr_db_ets`).

### Likely causes

*(Ordered, most probable first.)*

1. The node runs the in-memory ETS backend. ETS holds all data in the node's memory and discards it when the node stops; a restart, a crash, or a backend switch loses every provisioned subscriber. This is the shipped default backend.

### Diagnosis

1. Confirm the resolved backend at the node's console:
   ```erlang
   udr_db:backend().
   ```
   - Expected for a persistent deployment: `udr_db_mongo`.
   - If it is `udr_db_ets`, the data was in memory only and the restart discarded it — cause 1. This is by design, not a fault of the backend.
2. Confirm the timing: the lost subscribers were provisioned **before** the most recent restart, and a subscriber provisioned **after** the restart is present.
   - Expected on an ETS node: subscribers provisioned since the last start are present; those from before it are gone.

### Resolution

*(Normative.)*

- Where subscriber data is to survive a restart, a crash, or a backend switch, the MongoDB backend `shall` be selected in place of ETS, per the [data-store configuration reference §5.1](../configuration/data-store.md#51-backend) and [`RUN-BACKEND-001`](../operations/backend.md).
- While the ETS backend is in use, every provisioned subscriber `shall` be re-provisioned after each node restart, because no ETS data survives it.

> [!WARNING]
> The ETS backend is in-memory and has no persistence. Backup and restore ([`RUN-BACKUP-001`](../operations/backup-restore.md)) are meaningful only with the MongoDB backend. Reverting from MongoDB back to ETS, or restarting an ETS node, loses all data held in memory.

### Prevention

*(Informative.)* The persistence model is flagged at the top of the [operations README](../operations/README.md#persistence-model--read-this-first) precisely so this is not discovered after a restart. A deployment that needs durable subscriber data selects MongoDB before it provisions production subscribers.

### Related

- [Data-store configuration reference §5.1](../configuration/data-store.md#51-backend) — the ETS persistence warning.
- [`RUN-BACKEND-001`](../operations/backend.md) — migrate ETS → MongoDB.
- [`RUN-BACKUP-001`](../operations/backup-restore.md) — back up and restore (MongoDB only).
