# Troubleshooting: Cluster (`udr_cluster`)

**Applies to:** udr 0.1.0 · **Revised:** 2026-06-08

## Scope

This guide covers symptoms an operator observes when two or more `udr` nodes are meant to form one cluster: nodes that do not see each other over Erlang distribution, and the behavior of the per-[IMSI](../glossary.md) session lock when nodes are not interconnected. Clustering is established entirely by Erlang distribution (a distinct node name and a shared cookie); `udr_cluster` itself reads no configuration. The prerequisites are defined in the [cluster configuration reference](../configuration/cluster.md) and the [node configuration reference](../configuration/node.md); forming a cluster is the procedure [`RUN-CLUSTER-001`](../operations/cluster.md).

> [!NOTE]
> A single node forms a cluster of one and locks per-IMSI locally with no distribution configured. The symptoms below matter only when two or more nodes are to share the lock space.

---

## TS-CLUSTER-001: Nodes do not see each other

### Symptom

Two or more nodes that are meant to be clustered do not interconnect. On a node's console, `nodes()` does not list the expected peers, and `net_adm:ping/1` of a peer returns `pang` instead of `pong`. Per-IMSI locks taken on one node are not visible on another.

### Affected component

Erlang distribution between the nodes (node name, cookie, `epmd`, and the distribution port) — the prerequisite for `udr_cluster`'s shared lock space.

### Likely causes

*(Ordered, most probable first.)*

1. The nodes carry different `-setcookie` values. A cookie mismatch is refused and the nodes do not interconnect.
2. The nodes use short names (`-sname`) across different hosts. Short names do not interconnect across hosts; an FQDN `-name` is needed.
3. The node name does not resolve, or the distribution port or the [`epmd`](../glossary.md) port (TCP `4369`) is not reachable between the hosts.

### Diagnosis

1. Confirm the cookies match. On each node's console:
   ```erlang
   erlang:get_cookie().
   ```
   - Expected: the same atom on every node intended to cluster.
   - If the values differ, cause 1 applies.
2. Confirm the node names are distinct and of the right kind. On each node's console:
   ```erlang
   node().
   ```
   - Expected for a multi-host cluster: a distinct FQDN `name@fqdn` on each node, for example `'udr1@hss1.epc.example.net'`.
   - If the names are short (`name@shorthost`) and the nodes are on different hosts, cause 2 applies.
   - If two nodes share one name, that is its own fault: each node `shall` have a distinct name.
3. Confirm each node is registered with the port mapper and reachable. On each host:
   ```sh
   epmd -names
   ```
   - Expected: a line `name <node> at port <N>` for each local node.
   - From one host, confirm the other's `epmd` is reachable:
     ```sh
     nc -vz <other-host> 4369
     ```
   - If `epmd` is not listed or not reachable, or the distribution port is blocked, cause 3 applies.
4. With the above correct, ping the peer from one node's console:
   ```erlang
   net_adm:ping('udr2@hss2.epc.example.net').
   ```
   - Expected: `pong`, after which `nodes()` lists the peer.
   - `pang` means the nodes still did not interconnect; re-check causes 1–3.

### Resolution

*(Normative.)*

- For cause 1: every node intended to join one cluster `shall` carry the same `-setcookie` value, per the [node configuration reference §5.2](../configuration/node.md#52--setcookie). The shipped `udr_cookie` `should` be replaced with a unique secret before clustering across hosts.
- For cause 2: nodes on different hosts `shall` use `-name` with a fully-qualified `name@fqdn` value in place of `-sname`, per the [node configuration reference §5.1](../configuration/node.md#51--sname---name).
- For cause 3: each node name `shall` resolve, and the distribution port and the `epmd` port (TCP `4369`) `shall` be reachable between the nodes, per the [cluster configuration reference §5](../configuration/cluster.md#5-operational-prerequisites).
- After correcting the node name or cookie, which live in `config/vm.args`, the node `shall` be restarted, because those arguments are read at node start.

> [!CAUTION]
> The distribution cookie is a security boundary. A host that knows the cookie and can reach the distribution port can run code on every node in the mesh. Replace the shipped `udr_cookie` and restrict the distribution and `epmd` ports to a trusted network before clustering across hosts (see the [cluster configuration reference §5](../configuration/cluster.md#5-operational-prerequisites)).

### Prevention

*(Informative.)* Forming the cluster and confirming `nodes()` lists every peer is the procedure [`RUN-CLUSTER-001`](../operations/cluster.md); its [on-failure guidance](../operations/cluster.md#rollback--on-failure) gives the same cookie/name/`epmd` checks. Confirming interconnection before relying on cluster-wide locking avoids the partition behavior in [TS-CLUSTER-002](#ts-cluster-002-the-same-imsi-is-processed-concurrently-on-two-nodes-under-a-partition).

### Related

- [Cluster configuration reference §5, §7](../configuration/cluster.md#5-operational-prerequisites) — clustering prerequisites and interconnection checks.
- [Node configuration reference §5.1, §5.2](../configuration/node.md#51--sname---name) — node name and cookie.
- [`RUN-CLUSTER-001`](../operations/cluster.md) — form a cluster.

---

## TS-CLUSTER-002: The same IMSI is processed concurrently on two nodes under a partition

### Symptom

Across a cluster, two nodes appear to process signalling for the **same** subscriber at the same time — for example two near-simultaneous S6a procedures for one IMSI both proceed, where cluster-wide serialization was expected to make one wait. A query of the lock holder for that IMSI returns a different pid on each node, rather than a single shared owner.

### Affected component

`udr_cluster` — the per-IMSI session lock over [`syn`](../glossary.md) — and the Erlang distribution underneath it.

### Likely causes

*(Ordered, most probable first.)*

1. The nodes are not interconnected (a cookie mismatch, short names across hosts, or an unreachable distribution/`epmd` port — see [TS-CLUSTER-001](#ts-cluster-001-nodes-do-not-see-each-other)). When the nodes are not in one distribution mesh, each holds locks only locally, and two nodes can each believe they own the lock for one IMSI.
2. The cluster was interconnected but a network partition split it, so each side sees only its own members and registers the IMSI's lock independently within its own partition.

### Diagnosis

1. Confirm interconnection from each node's console:
   ```erlang
   nodes().
   ```
   - Expected: each node lists all the others.
   - If `nodes()` is empty or missing peers, the nodes are not in one mesh — cause 1; resolve via [TS-CLUSTER-001](#ts-cluster-001-nodes-do-not-see-each-other).
2. Confirm the lock holder is shared. Hold a lock for an IMSI on one node (inside a long-running `udr_cluster:with_session/2` call), then query the holder on another node:
   ```erlang
   udr_cluster:whereis_session(<<"001010000000001">>).
   ```
   - Expected when interconnected: the **pid on the holding node**, seen identically from every node.
   - If each node instead reports a local pid (or `undefined` while another node holds it), the lock space is not shared — cause 1 or cause 2.
3. Distinguish a partition from a never-formed cluster. If `nodes()` listed the peers earlier but does not now, the mesh was split after forming — cause 2; if it never listed them, the cluster never formed — cause 1.

### Resolution

*(Normative.)*

- For cause 1: the nodes `shall` be interconnected into one distribution mesh before cluster-wide serialization is relied upon, per [TS-CLUSTER-001](#ts-cluster-001-nodes-do-not-see-each-other) and the [cluster configuration reference §5](../configuration/cluster.md#5-operational-prerequisites). Until they are, each node serializes only its own traffic for an IMSI.
- For cause 2: the underlying network partition `shall` be repaired so the nodes rejoin one mesh; once `nodes()` lists every peer again, the per-IMSI lock is shared across the cluster.

> [!WARNING]
> When the nodes are not interconnected, each node holds per-IMSI locks only locally. Two nodes that both believe they hold the lock for one IMSI can process signalling for that subscriber concurrently. Confirm interconnection (`nodes()` lists every peer) before relying on cluster-wide serialization. This behavior is documented in the [cluster configuration reference §5](../configuration/cluster.md#5-operational-prerequisites).

> [!NOTE]
> The lock is advisory and scoped to one request: `with_session/2,3` acquires it for the duration of the handler and releases it when the handler returns, raises, or its process or node dies (confirmed in `udr_cluster.erl`). The acquire timeout (5000 ms) and retry interval (25 ms) are compile-time constants, not configuration; a caller that cannot acquire within the timeout receives `{error, session_busy}`.

### Prevention

*(Informative.)* Cluster-wide serialization depends on a healthy distribution mesh. Monitoring that `nodes()` lists the expected peers, and treating a shrinking peer list as an alarm, surfaces a partition before duplicate per-IMSI processing is observed.

### Related

- [TS-CLUSTER-001](#ts-cluster-001-nodes-do-not-see-each-other) — nodes not interconnected.
- [Cluster configuration reference §2, §5, §7](../configuration/cluster.md#2-terms) — the per-IMSI lock, the prerequisites, and the locking verification.
- [`RUN-CLUSTER-001`](../operations/cluster.md) — form and verify the cluster.
