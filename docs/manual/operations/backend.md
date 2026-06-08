# Operations Runbook: Select and Migrate the Data Backend

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers selecting the `udr_db` data backend — the default in-memory [ETS](../glossary.md) backend or the persistent [MongoDB](../glossary.md) backend — and migrating between them. It is for operators deciding where subscriber data lives and moving from one backend to the other. The backend parameters and the MongoDB connection options are defined in the [data-store configuration reference](../configuration/data-store.md); this runbook directs the operator through the switch and its consequences.

> [!CAUTION]
> The two backends do not share storage. Switching backends does **not** copy data between them. ETS data lives only in the node's memory and is discarded when the node stops; switching away from ETS (or restarting an ETS-backed node) loses every provisioned subscriber. Switching from MongoDB to ETS leaves the MongoDB data in place but the node stops reading it. Re-provisioning, or a MongoDB restore (see [`RUN-BACKUP-001`](backup-restore.md)), is the only way to populate the new backend.

---

## RUN-BACKEND-001: Switch the data backend (ETS ↔ MongoDB)

### Purpose

*(Informative.)* This procedure changes which storage module `udr_db` dispatches every read and write to. An operator runs it to move from the development-default ETS backend to persistent MongoDB (or back), understanding that data does not move with the setting.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node is running, per [`RUN-LIFECYCLE-001`](lifecycle.md), and the operator has confirmed which backend is currently in effect (see Verify, `udr_db:backend()`).
- For a switch **to** MongoDB: a reachable MongoDB server is available, and its host, port, database name, and (if authentication is used) the user, password, and auth source are known (see the [data-store configuration reference](../configuration/data-store.md) §5.2).
- The operator has accepted that the current backend's data does not migrate automatically, and has a plan to populate the new backend (re-provision per [`RUN-PROVISION-001`](provisioning.md), or restore per [`RUN-BACKUP-001`](backup-restore.md)).

### Inputs and privileges

- The target backend module: `udr_db_ets` or `udr_db_mongo`.
- For MongoDB: the connection map for `backend_opts` (host, port, database, and optional credentials).
- Permission to edit `config/sys.config` and to restart the node.

> [!IMPORTANT]
> `udr_db` caches the resolved backend in a `persistent_term` on first use. A change to `backend` does not take effect until the node restarts (see the [data-store configuration reference](../configuration/data-store.md) §3).

### Steps

1. **Capture the current data where it is to survive the switch.** If the current backend is MongoDB and the data is to be kept, take a backup first (see [`RUN-BACKUP-001`](backup-restore.md)). If the current backend is ETS, its data cannot be exported and `shall` be re-provisioned after the switch.
2. Set `backend` (and, for MongoDB, `backend_opts`) in `config/sys.config` under `udr_db`. To select MongoDB:

   ```erlang
   {udr_db, [
     {backend, udr_db_mongo},
     {backend_opts, #{
       host => "10.0.0.20",
       port => 27017,
       database => <<"hss">>,
       login => <<"hss_app">>,
       password => <<"s3cr3t">>,
       auth_source => <<"admin">>
     }}
   ]}
   ```

   To select ETS, set `{backend, udr_db_ets}` and `{backend_opts, #{}}`.
3. Restart the node so the new backend resolves, per [`RUN-LIFECYCLE-001`](lifecycle.md).
4. **Populate the new backend.** Re-provision subscribers (see [`RUN-PROVISION-001`](provisioning.md)), or, for MongoDB, restore a prior dump (see [`RUN-BACKUP-001`](backup-restore.md)).

### Verify

*(Observable outcome.)*

- Confirm which backend resolved. From the node console (see [`RUN-LIFECYCLE-001`](lifecycle.md)):

  ```erlang
  udr_db:backend().
  ```

  The result `shall` be the target module, `udr_db_ets` or `udr_db_mongo`.

- For the MongoDB backend, confirm the connection handle exists:

  ```erlang
  is_pid(udr_db_mongo_conn:conn()).
  ```

  The result `shall` be `true` once the backend has connected.

- End to end, provision a subscriber and read it back; a `GET` that returns `200 OK` with the subscriber document confirms the new backend stores and serves data (see [`RUN-PROVISION-001`](provisioning.md)). For MongoDB, restarting the node and reading the same subscriber back confirms persistence.

### Rollback / on failure

- If `udr_db:backend()` is not the target module, the `config/sys.config` change did not take effect or the node was not restarted; re-check the `udr_db` block and restart.
- If `udr_db_mongo_conn:conn()` is not a pid (or the call fails), the MongoDB backend could not connect; confirm the MongoDB server is reachable at the configured host and port and that any credentials are correct (see the [data-store configuration reference](../configuration/data-store.md) §5.2). The node `may` be reverted to ETS by restoring `{backend, udr_db_ets}` and restarting, at the cost of losing access to the MongoDB-stored data until the connection is fixed.
- To revert the switch, restore the previous `udr_db` block in `config/sys.config` and restart. Reverting the setting does not restore any data that was lost when an ETS-backed node stopped.

### Related

- [Data-store configuration reference](../configuration/data-store.md) — `backend`, `backend_opts`, and the MongoDB connection options.
- [`RUN-BACKUP-001`](backup-restore.md) — back up and restore the MongoDB data the new backend will read.
- [`RUN-PROVISION-001`](provisioning.md) — re-populate the new backend by provisioning.
