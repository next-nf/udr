# Configuration Reference: Node and Release

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the configuration of the [BEAM](../glossary.md) node and the [relx](../glossary.md) release, as distinct from any single [OTP application](../glossary.md). It documents the node-level arguments in `config/vm.args` (node name, distribution cookie, and the `+K` and `+A` emulator flags) and the release `mode` selected in `rebar.config`.

Application environment keys (the `udr_diameter`, `udr_sbi`, `udr_provision`, `udr_db`, `opentelemetry` blocks, and so on) are out of scope here; each is covered in its own reference under this directory. Erlang distribution and the shared cookie are summarized here because clustering depends on them; their effect on per-[IMSI](../glossary.md) locking is covered in the [cluster reference](cluster.md).

## 2. Terms

- **`vm.args`** — the [BEAM](../glossary.md) arguments file. Each line is an emulator or runtime flag passed to `erl` when the node starts, before any OTP application boots.
- **Distribution cookie** — the shared secret that two Erlang nodes present to each other to be allowed to form a distributed cluster. Two nodes interconnect only if their cookies match.
- **Release mode** — the relx packaging mode (`dev` or `prod`) that determines how the release directory is assembled.

## 3. Where configuration lives

Node-level arguments are in `config/vm.args`, bundled into the release by the `relx` section of `rebar.config`. The shipped file is:

```text
-sname udr

-setcookie udr_cookie

+K true
+A30
```

The release `mode` is set in the `relx` section of `rebar.config`:

```erlang
{relx, [
    {release, {udr, "0.1.0"}, [ ... ]},
    {mode, dev},
    {sys_config, "./config/sys.config"},
    {vm_args, "./config/vm.args"}
]}.
```

The `prod` profile overrides `mode` to `prod`:

```erlang
{profiles, [
    {prod, [{relx, [{mode, prod}]}]}
]}.
```

## 4. Parameter reference

| Parameter | Type | Default | Allowed values | Unit | Description | Effect | Since |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `-sname` | atom (short name) | `udr` | a short node name (no dot), or replace with `-name` for a fully-qualified name | — | The node name registered with [`epmd`](#52--sname---name) on the local host. | Sets the node identity used by Erlang distribution; peers address this node by `name@host`. | 0.1.0 |
| `-name` | atom (long name) | *not set* (the shipped file uses `-sname`) | a fully-qualified node name `name@fqdn` | — | The long node name, used in place of `-sname` for distribution across hosts. | Enables a node to interconnect across hosts that address each other by FQDN. | 0.1.0 |
| `-setcookie` | atom | `udr_cookie` | any atom | — | The Erlang distribution cookie. | Two nodes interconnect only if their cookies are equal; a mismatch is refused. | 0.1.0 |
| `+K` | boolean flag | `true` | `true`, `false` | — | Enables the kernel-poll I/O event mechanism in the emulator. | When `true`, the emulator uses scalable kernel polling for socket I/O. | 0.1.0 |
| `+A` | integer | `30` | a positive integer | threads | Size of the async thread pool used for I/O-bound built-in operations. | Sets how many async threads serve file and driver I/O. | 0.1.0 |
| `mode` (relx) | atom | `dev` | `dev`, `prod`, `minimal` | — | The relx release assembly mode, set in `rebar.config`. | `dev` symlinks code for fast rebuilds; `prod` copies a self-contained release for deployment. | 0.1.0 |

## 5. Parameter detail

### 5.1 `-sname` / `-name`

`-sname` and `-name` are mutually exclusive. The shipped file uses `-sname udr`, which names the node `udr@<shorthost>` and confines distribution to nodes on the same host with the same short name resolution.

- For a single-node deployment, the shipped `-sname udr` `may` be kept unchanged.
- When nodes on different hosts are to form a cluster, `-name` `shall` be used in place of `-sname`, with a fully-qualified `name@fqdn` value, because short names do not interconnect across hosts.
- Each node in a cluster `shall` have a node name distinct from every other node's.

> [!NOTE]
> The node name is part of the cluster prerequisite, not an application key. The cluster reference describes how per-IMSI locking depends on it.

### 5.2 `-setcookie`

The cookie is a shared secret, not a tuning parameter.

- Every node intended to join one cluster `shall` carry the same `-setcookie` value.
- The shipped value `udr_cookie` `should` be replaced before any deployment reachable from an untrusted network.

> [!CAUTION]
> The cookie is a security boundary for Erlang distribution. Any host that knows the cookie and can reach the distribution port can execute code on the node. The shipped value `udr_cookie` is well-known; leaving it in place on a reachable node is a remote-code-execution exposure. Set a unique, secret cookie and restrict access to the distribution port.

### 5.3 `mode` (relx)

`mode` is set in `rebar.config`, not in `vm.args`.

- For local development, the default `dev` mode `may` be used; `rebar3 release` assembles a `dev`-mode release that symlinks application code for fast iteration.
- For deployment, the release `should` be built with the `prod` profile (`rebar3 as prod release`), which assembles a self-contained `prod`-mode release.

> [!NOTE]
> `minimal` mode is available in relx to exclude the Erlang runtime system (ERTS) from the release. It is mentioned in `rebar.config` as a commented alternative and is not selected by any shipped profile.

## 6. Example

A two-host cluster member, named for distribution across hosts with a secret cookie:

```text
-name udr1@hss1.epc.example.net

-setcookie s3cr3t-shared-cookie

+K true
+A30
```

This names the node `udr1@hss1.epc.example.net` so a second node `udr2@hss2.epc.example.net` carrying the same cookie can interconnect with it.

## 7. Verify

- Confirm the node name and cookie took effect. From the running Erlang shell:

  ```erlang
  {node(), erlang:get_cookie()}.
  ```

  The result `shall` be the configured node name and cookie, for example `{'udr1@hss1.epc.example.net', 's3cr3t-shared-cookie'}`.

- Confirm the node is registered with the port mapper:

  ```sh
  epmd -names
  ```

  The output lists a line `name udr at port <N>` for the configured short name.

- Confirm two nodes interconnect (run from one node's shell, naming the other):

  ```erlang
  net_adm:ping('udr2@hss2.epc.example.net').
  ```

  A successful interconnection returns the atom `pong`; a cookie mismatch or unreachable peer returns `pang`.
