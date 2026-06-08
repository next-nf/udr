# Configuration Reference: Cluster (`udr_cluster`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## 1. Scope

This reference covers the `udr_cluster` application: cluster-wide per-[IMSI](../glossary.md) session locking over [`syn`](../glossary.md). It documents how clustering is configured.

`udr_cluster` reads **no application environment** and exposes **no operator-tunable key** of its own. The session-acquire timeout (5000 ms) and retry interval (25 ms) are compile-time constants in `udr_cluster`, not configuration. What an operator configures for clustering therefore lives entirely at the node level: Erlang distribution and the shared cookie. This reference documents those operational prerequisites and how locking behaves; the node-level keys themselves are defined in the [node reference](node.md).

## 2. Terms

- **Per-IMSI session lock** — a cluster-wide lock that gives one subscriber a single owner across all connected nodes for the duration of a request, so that concurrent signalling for one IMSI serializes. It is provided by `udr_cluster` over [`syn`](../glossary.md).
- **`syn` scope** — the named [`syn`](../glossary.md) registry scope (`udr_session`) in which the per-IMSI locks are registered. Every node joins this scope at start.

## 3. Where configuration lives

`udr_cluster` has no `config/sys.config` block. The clustering behavior is determined by the node-level settings in `config/vm.args` (see the [node reference](node.md)):

- the node name (`-sname` or `-name`), and
- the distribution cookie (`-setcookie`).

`udr_cluster_app` joins the local node to the `udr_session` [`syn`](../glossary.md) scope at start; no configuration selects or disables this.

> [!NOTE]
> A single node forms a cluster of one. Per-IMSI locking works on one node with no distribution configured at all; the prerequisites below matter only when two or more nodes are to share the lock space.

## 4. Parameter reference

`udr_cluster` defines no configuration parameters. The clustering prerequisites are node-level parameters defined elsewhere:

| Parameter | Owning reference | Default | Role in clustering |
| --- | --- | --- | --- |
| `-name` / `-sname` | [Node and release](node.md) | `-sname udr` | Gives each node a distinct distributed identity. For multi-host clusters, `-name` with an FQDN is used. |
| `-setcookie` | [Node and release](node.md) | `udr_cookie` | The shared secret; nodes interconnect only if their cookies match. |

> [!IMPORTANT]
> There is no `udr_cluster` key to enable or size clustering. Clustering is established entirely by Erlang distribution: give each node a distinct name and a shared cookie, and connect them.

## 5. Operational prerequisites

For two or more nodes to share the per-IMSI lock space, all of the following apply:

- Each node `shall` run with a distinct node name (`-name`, an FQDN, for a multi-host cluster).
- Every node `shall` carry the same `-setcookie` value; a cookie mismatch prevents the nodes from interconnecting and therefore from sharing locks.
- The Erlang distribution port and the [`epmd`](../glossary.md) port (TCP `4369`) `shall` be reachable between the nodes.
- The nodes `shall` be connected into one distribution mesh (for example with `net_adm:ping/1` between them, or an equivalent cluster-formation mechanism).

> [!CAUTION]
> The distribution cookie is a security boundary. A host that knows the cookie and can reach the distribution port can run code on every node in the mesh. Replace the shipped `udr_cookie` and restrict the distribution and `epmd` ports to a trusted network before clustering across hosts.

> [!WARNING]
> When the nodes are not interconnected (for example because of a cookie mismatch or an unreachable distribution port), each node holds locks only locally. Two nodes that both believe they hold the lock for one IMSI can then process signalling for that subscriber concurrently. Confirm interconnection (§7) before relying on cluster-wide serialization.

## 6. Example

Two nodes form one lock space by sharing a cookie and interconnecting. The relevant `config/vm.args` on each node:

Node 1:

```text
-name udr1@hss1.epc.example.net
-setcookie s3cr3t-shared-cookie
```

Node 2:

```text
-name udr2@hss2.epc.example.net
-setcookie s3cr3t-shared-cookie
```

With both started and interconnected, a per-IMSI lock taken on either node is visible to the other, so signalling for one subscriber serializes across both.

## 7. Verify

- Confirm the nodes are interconnected. From node 1's Erlang shell:

  ```erlang
  nodes().
  ```

  The result `shall` list `'udr2@hss2.epc.example.net'` (and every other peer).

- Confirm the session scope is active on each node. On each node:

  ```erlang
  udr_cluster:scope().
  ```

  The result `shall` be the atom `udr_session`, the scope each node joins at start.

- Confirm cluster-wide locking. Hold a lock for an IMSI on node 1 (inside a long-running `udr_cluster:with_session/2` call), then on node 2 query the holder:

  ```erlang
  udr_cluster:whereis_session(<<"001010000000001">>).
  ```

  The result `shall` be the pid on node 1, showing both nodes see the same lock owner.
