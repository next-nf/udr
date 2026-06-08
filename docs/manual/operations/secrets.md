# Operations Runbook: Manage Secret Material Safely

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This runbook covers handling the long-term subscriber secrets — the permanent key [Ki](../glossary.md) and the operator key material [OPc](../glossary.md)/[OP](../glossary.md) — and the Erlang distribution cookie, across the paths where they appear: the provisioning API, the data store, the [SBI](../glossary.md), backups, and `config/vm.args`. It is for operators establishing safe practice for secret material. It states what `shall` and `should` be done; the underlying parameters and interfaces are defined in the references it links.

> [!CAUTION]
> Ki and OPc are the root of EPS-AKA authentication. Disclosure of a subscriber's Ki (and OPc) lets an attacker impersonate that subscriber or the network. These values `shall` be treated as high-value secrets at every point they appear, including configuration files, request bodies, the data store, backups, and logs.

---

## RUN-SECRETS-001: Handle Ki, OPc, and the distribution cookie safely

### Purpose

*(Informative.)* This procedure establishes the practices that keep secret material from leaking through the system's interfaces and artifacts: where each secret travels in clear, how to limit who can read it, and how to confirm exposure is closed off. An operator runs it once when standing up a deployment and revisits it on review.

### Pre-conditions

*(Normative.)* The following `shall` hold before starting:

- The node is deployed and its listener bind addresses are known (see the [provisioning](../configuration/provisioning.md), [SBI](../configuration/sbi.md), and [S6a Diameter](../configuration/diameter.md) configuration references).
- The operator can edit `config/sys.config` and `config/vm.args`, restart the node ([`RUN-LIFECYCLE-001`](lifecycle.md)), and control network reachability of the listeners.

### Inputs and privileges

- The operational Ki, OPc (or OP), and AMF values for each subscriber.
- The intended trusted management network for the provisioning and SBI listeners.
- A unique distribution cookie value to replace the shipped default.

### Steps

1. **Source operational secrets from a trusted store, never from examples.** Operational Ki and OPc values `shall not` be drawn from public test vectors (such as those used in [quickstart.md](../quickstart.md) and the runbook examples). Provision them per [`RUN-PROVISION-001`](provisioning.md).

2. **Provision OPc rather than OP where the operator key is sensitive.** The provisioning API accepts either `opc` (used directly) or `op` (from which OPc is derived at provisioning time); see the [provisioning interface reference](../interfaces/provisioning.md) §5.1. Supplying `opc` keeps the operator-wide OP off the wire and out of this node.

3. **Bind the provisioning and SBI listeners to a trusted management interface only.** Both are unauthenticated. The provisioning API accepts Ki/OPc on `PUT` in clear, and the SBI authentication-subscription resource **returns** Ki and OPc in clear hex (confirmed in `udr_sbi.erl`, `auth_view/1`, which hex-encodes `ki`, `opc`, and `amf`). The bind addresses `shall` be restricted to a trusted network; see the [provisioning configuration reference](../configuration/provisioning.md) and the [SBI configuration reference](../configuration/sbi.md).

4. **Protect backups as secret material.** A MongoDB backup archive contains every subscriber's Ki and OPc; it `shall` be stored and transferred with the same protection as the live data (see [`RUN-BACKUP-001`](backup-restore.md)).

5. **Replace the distribution cookie and restrict the distribution ports.** The shipped `-setcookie udr_cookie` is well-known. Set a unique secret cookie in `config/vm.args`, and restrict the Erlang distribution port and the [`epmd`](../glossary.md) port to a trusted network; see the [node reference](../configuration/node.md) §5.2.

   > [!NOTE]
   > The shipped release reads `config/sys.config` and `config/vm.args` directly; OS-environment substitution into these files (relx `sys_config_src`/`vm_args_src`) is not enabled in `rebar.config` (it is present only as a commented option). Secrets placed in these files therefore live in the files on disk; restrict the files' permissions accordingly.

6. **Keep secrets out of shared logs.** Avoid pasting `PUT` bodies or SBI authentication-subscription responses (which carry Ki/OPc) into shared terminals, tickets, or logs.

### Verify

*(Observable outcome.)*

- Confirm the provisioning listener is not reachable from an untrusted host: from such a host, a request to the provisioning port `shall` fail to connect (for example `curl` reports connection refused or times out). From the trusted management network, the same request reaches the listener (a `GET` for an unknown IMSI returns `404`; see [`RUN-PROVISION-001`](provisioning.md)).

- Confirm the SBI authentication-subscription resource is not reachable from an untrusted host in the same way; from the trusted network it returns `200 OK` with the hex-encoded `ki`/`opc` for a provisioned subscriber (see [quickstart.md](../quickstart.md) §5.1). The observable point is that the secret-bearing resource answers **only** on the trusted interface.

- Confirm the distribution cookie was changed from the shipped default. From the node console (see [`RUN-LIFECYCLE-001`](lifecycle.md)):

  ```erlang
  erlang:get_cookie().
  ```

  The result `shall` be the unique value set in Step 5, and `shall not` be `udr_cookie`.

### Rollback / on failure

- If a secret-bearing listener is found reachable from an untrusted network, restrict its bind address (or the surrounding firewall) and restart, per [`RUN-LIFECYCLE-001`](lifecycle.md); re-run the reachability Verify.
- If `erlang:get_cookie()` still returns `udr_cookie`, the `config/vm.args` change did not take effect; correct the file and restart.
- If a Ki/OPc value is suspected to have leaked, treat the affected subscribers' credentials as compromised: rotate Ki/OPc at the source and re-provision the affected IMSIs per [`RUN-PROVISION-001`](provisioning.md). Rotation at the network's secret store is out of scope of this node.

### Related

- [`RUN-PROVISION-001`](provisioning.md) — where Ki/OPc enter the system.
- [`RUN-BACKUP-001`](backup-restore.md) — backups that contain secret material.
- [Provisioning configuration reference](../configuration/provisioning.md) and [SBI configuration reference](../configuration/sbi.md) — binding the secret-bearing listeners.
- [Node and release configuration reference](../configuration/node.md) §5.2 — the distribution cookie as a security boundary.
- [Provisioning interface reference](../interfaces/provisioning.md) §5.1 — `opc` versus `op`.
