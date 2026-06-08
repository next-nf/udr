# Operations Runbook: Upgrade to a New Version

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers replacing a deployed `udr` release with a newer build. It is for operators moving a node (or a cluster) from one version to the next. Building and first deployment are covered in [`RUN-DEPLOY-001`](deploy.md); start and stop are covered in [`RUN-LIFECYCLE-001`](lifecycle.md).

> [!IMPORTANT]
> This release does not ship Erlang hot-code-upgrade artifacts (no `.appup`/`.relup` files are configured in `rebar.config`). An upgrade is therefore a **cold** replacement: stop the node, swap the release directory, and start it again. There is a service interruption for the duration; in a cluster it is mitigated by upgrading one node at a time (a rolling upgrade).

> [!CAUTION]
> With the default in-memory [ETS](../glossary.md) backend, stopping the node for the upgrade discards all provisioned subscriber data, which `shall` be re-provisioned after the upgrade. Where data is to survive the upgrade, the [MongoDB](../glossary.md) backend `shall` be in use and a backup `shall` be taken first (see [`RUN-BACKUP-001`](backup-restore.md)).

---

## RUN-UPGRADE-001: Replace a deployed release with a new version

### Purpose

*(Informative.)* This procedure brings a node onto a new build by stopping the running release, putting the new release directory in place, and starting it, preserving the operator's configuration and (for the MongoDB backend) the subscriber data. An operator runs it to apply a new version.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The new version has been built as a `prod`-mode release per [`RUN-DEPLOY-001`](deploy.md), and its release directory is available on, or copyable to, the target host.
- The current `config/sys.config` and `config/vm.args` values are known, so they can be carried into the new release.
- For the MongoDB backend: a fresh backup has been taken and verified (see [`RUN-BACKUP-001`](backup-restore.md)).
- For the ETS backend: the operator has accepted that provisioned data is lost across the restart and has the means to re-provision it (see [`RUN-PROVISION-001`](provisioning.md)).
- In a cluster, the operator upgrades one node at a time and the remaining nodes continue to serve.

### Inputs and privileges

- The new release directory (for example a new `_build/prod/rel/udr`).
- The current configuration files.
- Permission to stop and start the node and to replace the release directory on disk.

### Steps

1. **Back up first.** For the MongoDB backend, take and verify a backup (see [`RUN-BACKUP-001`](backup-restore.md)). For the ETS backend, no backup is possible; confirm the re-provisioning source is ready.
2. **Carry the configuration into the new release.** Place the current `config/sys.config` and `config/vm.args` into the new build before assembling it, or copy them into the new release directory's config location, so the new version starts with the same backend, identity, listeners, node name, and cookie.
3. **Stop the running node**, per [`RUN-LIFECYCLE-001`](lifecycle.md):

   ```sh
   _build/prod/rel/udr/bin/udr stop
   ```

4. **Put the new release in place.** Move the old release directory aside (for example rename it to `udr.prev`) and place the new release directory at the deployment path. Keeping the old directory enables the rollback below.
5. **Start the new node**, per [`RUN-LIFECYCLE-001`](lifecycle.md):

   ```sh
   _build/prod/rel/udr/bin/udr daemon
   ```

6. **Restore or re-provision data as needed.** For the MongoDB backend, the data is read from the unchanged database; restore from the backup only if the database itself was affected (see [`RUN-BACKUP-001`](backup-restore.md)). For the ETS backend, re-provision subscribers (see [`RUN-PROVISION-001`](provisioning.md)).
7. **In a cluster, repeat for each node** in turn, confirming the upgraded node has rejoined the mesh before proceeding to the next (see [`RUN-CLUSTER-001`](cluster.md)).

### Verify

*(Observable outcome.)*

- Confirm the node is up on the new version:

  ```sh
  _build/prod/rel/udr/bin/udr ping
  ```

  The response `shall` be `pong`.

- Confirm the running release version. From the node console (see [`RUN-LIFECYCLE-001`](lifecycle.md)):

  ```erlang
  application:which_applications().
  ```

  The `udr` entry `shall` show the new version string.

- Confirm service is restored: a `GET` for a known subscriber returns `200 OK` (for the MongoDB backend, the data persists across the upgrade; for ETS, after re-provisioning). See [`RUN-PROVISION-001`](provisioning.md).

- In a cluster, confirm the upgraded node rejoined: `nodes()` on a peer `shall` list it (see [`RUN-CLUSTER-001`](cluster.md)).

### Rollback / on failure

- If the new node does not return `pong`, or a Verify fails, stop it (`_build/prod/rel/udr/bin/udr stop`), restore the previous release directory (the `udr.prev` from Step 4), and start it again. The previous version then runs with the unchanged configuration.
- For the MongoDB backend, if the new version is found to have corrupted or migrated the data unacceptably, restore the pre-upgrade backup (see [`RUN-BACKUP-001`](backup-restore.md)) after rolling the release back.
- For the ETS backend, a rollback returns to the previous code but not to the pre-upgrade data, which was already lost at the stop in Step 3; re-provision against the previous version.

### Related

- [`RUN-DEPLOY-001`](deploy.md) — build the new release this runbook installs.
- [`RUN-LIFECYCLE-001`](lifecycle.md) — stop and start the node.
- [`RUN-BACKUP-001`](backup-restore.md) — back up before upgrading; restore on failure.
- [`RUN-CLUSTER-001`](cluster.md) — rolling a cluster one node at a time.
