# Operations Runbook: Node Lifecycle

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers the lifecycle of a deployed `udr` node: starting it, stopping it, restarting it, and attaching an interactive Erlang console to it. It is for operators running a `prod`-mode [relx](../glossary.md) release produced by [`RUN-DEPLOY-001`](deploy.md). Building and first-time placement of the release are covered in that runbook.

> [!CAUTION]
> With the default in-memory [ETS](../glossary.md) backend, stopping or restarting the node discards all provisioned subscriber data. Where data is to survive a restart, the [MongoDB](../glossary.md) backend `shall` be selected (see the [data-store configuration reference](../configuration/data-store.md) and [`RUN-BACKEND-001`](backend.md)) before relying on any stop or restart.

---

## RUN-LIFECYCLE-001: Start, stop, restart, and attach a console

### Purpose

*(Informative.)* This procedure gives the operator the day-to-day controls for a deployed node: bring it up as a background service, take it down cleanly, restart it, and open a console for inspection or for the Erlang-shell verification steps that other runbooks use.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- A `prod`-mode release has been deployed to the host, per [`RUN-DEPLOY-001`](deploy.md), so that `_build/prod/rel/udr/bin/udr` (or the deployed equivalent path) exists.
- The operator has permission to run the release control script and, for `start`, to bind the configured listener ports.
- For the console and remote-console subcommands, the `config/vm.args` node name and cookie are known, because a remote console connects over Erlang distribution.

### Inputs and privileges

- The path to the release control script, here `_build/prod/rel/udr/bin/udr`.
- The node name and distribution cookie from `config/vm.args` (for `remote_console`).

### Steps

> [!NOTE]
> The subcommands below are the standard relx release-script subcommands. The exact set on a given build is printed by running `_build/prod/rel/udr/bin/udr` with no arguments; confirm against that output if a subcommand differs.

1. **Start as a background service.** Run:

   ```sh
   _build/prod/rel/udr/bin/udr daemon
   ```

2. **Start in the foreground with an attached console.** Run:

   ```sh
   _build/prod/rel/udr/bin/udr console
   ```

   This boots the node and leaves an interactive Erlang shell in the terminal; closing the terminal stops the node.

3. **Attach a console to an already-running node** (started with `daemon`), without stopping it:

   ```sh
   _build/prod/rel/udr/bin/udr remote_console
   ```

   This opens a remote Erlang shell over distribution. To leave the remote console without stopping the node, detach with `Ctrl-G`, then `q` — not `Ctrl-C`, which on a foreground `console` would stop the node.

4. **Stop the node cleanly.** Run:

   ```sh
   _build/prod/rel/udr/bin/udr stop
   ```

5. **Restart the node.** Stop it (Step 4), then start it (Step 1):

   ```sh
   _build/prod/rel/udr/bin/udr stop
   _build/prod/rel/udr/bin/udr daemon
   ```

### Verify

*(Observable outcome.)*

- After Step 1, 2, or 5 (start/restart), confirm the node is up:

  ```sh
  _build/prod/rel/udr/bin/udr ping
  ```

  The response `shall` be `pong`.

- After a start, confirm the umbrella applications are running. From a console (Step 2 or 3):

  ```erlang
  [ A || {A,_,_} <- application:which_applications(),
         lists:member(A, [udr, udr_hss, udr_diameter, udr_sbi, udr_provision]) ].
  ```

  The result `shall` list all five applications (order may vary):

  ```erlang
  [udr_provision,udr_sbi,udr_diameter,udr_hss,udr]
  ```

- After Step 4 (stop), confirm the node is down:

  ```sh
  _build/prod/rel/udr/bin/udr ping
  ```

  The response `shall` be `Node 'udr@<host>' not responding to pings.` and the command exits non-zero.

### Rollback / on failure

- If `ping` does not return `pong` after a start, the node did not boot. Run `_build/prod/rel/udr/bin/udr console` in the foreground to see the boot error directly, or inspect the release log under `_build/prod/rel/udr/log/`.
- If `remote_console` cannot attach (it reports it cannot connect to the node), confirm the node is running (`ping`), that the cookie in `config/vm.args` matches, and that [`epmd`](../glossary.md) is reachable (`epmd -names` lists the node).
- If `stop` does not bring the node down within the script's timeout, identify the OS process and terminate it, then confirm with `ping` that the node is down before restarting.

### Related

- [`RUN-DEPLOY-001`](deploy.md) — build and place the release this runbook controls.
- [`RUN-UPGRADE-001`](upgrade.md) — stop/start as part of replacing a version.
- [Node and release configuration reference](../configuration/node.md) — node name and cookie used by `remote_console`.
