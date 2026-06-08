# Operations Runbook: Back Up and Restore (MongoDB Backend)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers backing up and restoring subscriber data when the node uses the [MongoDB](../glossary.md) backend. It is for operators protecting the subscriber base against loss and recovering it. The backend selection and its connection options are defined in the [data-store configuration reference](../configuration/data-store.md).

> [!CAUTION]
> Backup and restore apply **only** to the MongoDB backend. The default in-memory [ETS](../glossary.md) backend keeps all data in the node's memory and offers no export; there is no way to back up an ETS-backed node, and its data is lost when the node stops. Where data is to be backed up, the MongoDB backend `shall` be selected first (see [`RUN-BACKEND-001`](backend.md)). This runbook does not attempt to back up ETS data.

> [!NOTE]
> `mongodump` and `mongorestore` are MongoDB's own database tools. They operate directly on the MongoDB server, independent of the HSS node. They are not part of this project and are run from a host that can reach the MongoDB server.

---

## RUN-BACKUP-001: Back up and restore the subscriber database

### Purpose

*(Informative.)* This procedure captures the HSS's MongoDB database to a portable archive and restores it. An operator runs the backup on a schedule or before a risky change (an upgrade, a backend migration), and runs the restore to recover the subscriber base or to populate a new node.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node uses the MongoDB backend (`udr_db` `backend` is `udr_db_mongo`), confirmed by `udr_db:backend()` returning `udr_db_mongo` (see [`RUN-BACKEND-001`](backend.md)).
- The MongoDB database name configured in `backend_opts` is known (shipped default `udr`; the [data-store configuration reference](../configuration/data-store.md) §5.2 example uses `hss`).
- The MongoDB server is reachable from the host running the backup tools, and any required MongoDB credentials are available.
- The MongoDB database tools `mongodump` and `mongorestore` are installed on that host.

### Inputs and privileges

- The MongoDB connection details: host, port, database name, and (if authentication is enabled) user, password, and authentication database — the same values configured in `backend_opts`.
- A destination path for the backup archive, and read access to it for a restore.
- MongoDB privileges sufficient to read the database (backup) and to write it (restore).

> [!CAUTION]
> A backup archive contains the long-term key material ([Ki](../glossary.md) and [OPc](../glossary.md)) for every subscriber, in the database's stored form. The archive `shall` be stored and transferred with the same protection as the live secret material; see [`RUN-SECRETS-001`](secrets.md).

### Steps

1. **Back up the database.** Run `mongodump` against the configured database, writing a gzipped archive (replace the host, port, database, and credentials with the configured values):

   ```sh
   mongodump \
     --host 10.0.0.20 --port 27017 \
     --username hss_app --password 's3cr3t' --authenticationDatabase admin \
     --db hss \
     --gzip --archive=hss-$(date +%Y%m%d-%H%M%S).archive
   ```

   Omit the `--username`, `--password`, and `--authenticationDatabase` options where the MongoDB server requires no authentication.
2. **Store the archive** in the protected backup location.
3. **Restore the database** from an archive when recovering. Run `mongorestore` against the target MongoDB server:

   ```sh
   mongorestore \
     --host 10.0.0.20 --port 27017 \
     --username hss_app --password 's3cr3t' --authenticationDatabase admin \
     --gzip --archive=hss-20260608-120000.archive --drop
   ```

   The `--drop` option replaces each collection from the archive; omit it to merge into existing data.
4. **Make the node read the restored data.** Where the node was running against a database that was just replaced, restart the node so it reconnects cleanly to the restored database, per [`RUN-LIFECYCLE-001`](lifecycle.md).

### Verify

*(Observable outcome.)*

- Backup (Step 1): `mongodump` `shall` exit with status `0` and the named `.archive` file `shall` exist and be non-empty:

  ```sh
  ls -l hss-*.archive
  ```

- Restore (Step 3): `mongorestore` `shall` exit with status `0` and report the number of documents restored.

- End to end: after the restore and node restart, read back a subscriber known to be in the archive through the provisioning API; the `GET` `shall` return `200 OK` with that subscriber's read view (see [`RUN-PROVISION-001`](provisioning.md) and the [provisioning interface reference](../interfaces/provisioning.md) §5.2). This confirms the restored data is served by the node.

### Rollback / on failure

- If `mongodump` exits non-zero, no usable archive was produced; confirm the host can reach the MongoDB server and that the credentials and database name are correct, then repeat. Do not rely on a partial archive.
- If `mongorestore` exits non-zero, the target database `may` be partially written; restore again with `--drop` from a known-good archive to return to a consistent state.
- If, after a restore, the node does not serve a restored subscriber, confirm the node's `backend_opts` `database` matches the database that was restored into, and that the node was restarted (Step 4).

### Related

- [`RUN-BACKEND-001`](backend.md) — select the MongoDB backend that this runbook backs up.
- [Data-store configuration reference](../configuration/data-store.md) — the MongoDB connection options that name the database.
- [`RUN-SECRETS-001`](secrets.md) — protecting the secret material a backup contains.
- [`RUN-UPGRADE-001`](upgrade.md) — back up before upgrading.
